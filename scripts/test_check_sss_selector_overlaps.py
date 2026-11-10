#!/usr/bin/env python3

import unittest

from check_sss_selector_overlaps import (
    BOOT_IMAGE_PATCH_TARGET,
    CLUSTER_PLATFORM_LABEL,
    CLUSTER_TYPE_LABEL,
    DEFAULT_TEMPLATE,
    FEDRAMP_LABEL,
    MANAGED_LABEL,
    PRODUCT_LABEL,
    VERSION_LABEL,
    find_overlaps,
    load_patch_targets,
    selector_matches,
)


class SelectorMatchesTests(unittest.TestCase):
    def test_match_labels_require_exact_value(self):
        selector = {"matchLabels": {"example.com/tier": "prod"}}
        self.assertTrue(selector_matches(selector, {"example.com/tier": "prod"}))
        self.assertFalse(selector_matches(selector, {}))
        self.assertFalse(selector_matches(selector, {"example.com/tier": "stage"}))

    def test_in_requires_present_key_and_matching_value(self):
        selector = {
            "matchExpressions": [
                {"key": "example.com/tier", "operator": "In", "values": ["prod"]}
            ]
        }
        self.assertTrue(selector_matches(selector, {"example.com/tier": "prod"}))
        self.assertFalse(selector_matches(selector, {}))
        self.assertFalse(selector_matches(selector, {"example.com/tier": "stage"}))

    def test_not_in_matches_absent_key(self):
        selector = {
            "matchExpressions": [
                {"key": "example.com/tier", "operator": "NotIn", "values": ["rosa"]}
            ]
        }
        self.assertTrue(selector_matches(selector, {}))
        self.assertTrue(selector_matches(selector, {"example.com/tier": "osd"}))
        self.assertFalse(selector_matches(selector, {"example.com/tier": "rosa"}))

    def test_exists_and_does_not_exist(self):
        exists = {
            "matchExpressions": [
                {"key": "example.com/tier", "operator": "Exists"}
            ]
        }
        missing = {
            "matchExpressions": [
                {"key": "example.com/tier", "operator": "DoesNotExist"}
            ]
        }
        self.assertTrue(selector_matches(exists, {"example.com/tier": "osd"}))
        self.assertFalse(selector_matches(exists, {}))
        self.assertTrue(selector_matches(missing, {}))
        self.assertFalse(selector_matches(missing, {"example.com/tier": "osd"}))

    def test_unknown_operator_fails(self):
        selector = {
            "matchExpressions": [
                {"key": "example.com/tier", "operator": "Equals", "values": ["osd"]}
            ]
        }
        with self.assertRaises(ValueError):
            selector_matches(selector, {"example.com/tier": "osd"})


class PatchTargetOverlapTests(unittest.TestCase):
    def test_overlapping_selectors_are_reported(self):
        target = ("MachineConfiguration", "openshift-machine-config-operator", "cluster")
        targets = {
            target: {
                "first": {"matchLabels": {MANAGED_LABEL: "true"}},
                "second": {
                    "matchExpressions": [
                        {"key": VERSION_LABEL, "operator": "NotIn", "values": ["4.0"]}
                    ]
                },
            }
        }
        fleet = [{MANAGED_LABEL: "true", VERSION_LABEL: "4.22"}]

        overlaps = find_overlaps(targets, fleet)

        self.assertEqual(1, len(overlaps))
        self.assertEqual(target, overlaps[0][0])
        self.assertEqual(["first", "second"], overlaps[0][2])


class GeneratedTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        targets = load_patch_targets(DEFAULT_TEMPLATE)
        if BOOT_IMAGE_PATCH_TARGET not in targets:
            raise AssertionError(
                "generated production template is missing the boot-image patch target"
            )
        cls.syncsets = targets[BOOT_IMAGE_PATCH_TARGET]

    def matching_names(self, labels):
        return sorted(
            name
            for name, selector in self.syncsets.items()
            if selector_matches(selector, labels)
        )

    def test_supported_versions_match_exactly_one_expected_sss(self):
        cases = [
            ("4.18", "osd-machine-configuration-osd-aws"),
            ("4.19", "osd-machine-configuration-osd-aws-419"),
            ("4.20", "osd-machine-configuration-osd-aws-419"),
            ("4.21", "osd-machine-configuration-osd-aws-419"),
            ("4.22", "osd-machine-configuration-osd-aws-422"),
            ("4.23", "osd-machine-configuration-osd-aws-422"),
            ("4.40", "osd-machine-configuration-osd-aws-422"),
            ("5.0", "osd-machine-configuration-osd-aws-422"),
        ]
        for version, expected in cases:
            labels = {
                MANAGED_LABEL: "true",
                VERSION_LABEL: version,
                CLUSTER_PLATFORM_LABEL: "aws",
                PRODUCT_LABEL: "osd",
            }
            with self.subTest(version=version):
                self.assertEqual([expected], self.matching_names(labels))

    def test_fedramp_422_and_later_matches_only_managed_cpms_sss(self):
        expected = ["osd-machine-configuration-osd-aws-422"]
        for version in ("4.22", "4.23", "4.40", "5.0"):
            for product in (None, "osd"):
                labels = {
                    MANAGED_LABEL: "true",
                    VERSION_LABEL: version,
                    CLUSTER_PLATFORM_LABEL: "aws",
                    FEDRAMP_LABEL: "true",
                }
                if product is not None:
                    labels[PRODUCT_LABEL] = product
                with self.subTest(version=version, product=product):
                    self.assertEqual(expected, self.matching_names(labels))

    def test_fedramp_419_through_421_matches_only_legacy_sss(self):
        expected = ["osd-machine-configuration-osd-aws-419"]
        for version in ("4.19", "4.20", "4.21"):
            for product in (None, "osd"):
                labels = {
                    MANAGED_LABEL: "true",
                    VERSION_LABEL: version,
                    CLUSTER_PLATFORM_LABEL: "aws",
                    FEDRAMP_LABEL: "true",
                }
                if product is not None:
                    labels[PRODUCT_LABEL] = product
                with self.subTest(version=version, product=product):
                    self.assertEqual(expected, self.matching_names(labels))

    def test_new_sss_excludes_out_of_scope_clusters(self):
        name = "osd-machine-configuration-osd-aws-422"
        self.assertIn(name, self.syncsets)
        selector = self.syncsets[name]
        base = {
            MANAGED_LABEL: "true",
            VERSION_LABEL: "4.22",
            CLUSTER_PLATFORM_LABEL: "aws",
            PRODUCT_LABEL: "osd",
        }
        cases = [
            ("ROSA", {**base, PRODUCT_LABEL: "rosa"}),
            (
                "FedRAMP ROSA",
                {**base, PRODUCT_LABEL: "rosa", FEDRAMP_LABEL: "true"},
            ),
            ("GCP", {**base, CLUSTER_PLATFORM_LABEL: "gcp"}),
            ("Azure", {**base, CLUSTER_PLATFORM_LABEL: "azure"}),
            (
                "management-cluster",
                {**base, CLUSTER_TYPE_LABEL: "management-cluster"},
            ),
            (
                "management-cluster-v2",
                {**base, CLUSTER_TYPE_LABEL: "management-cluster-v2"},
            ),
            ("service-cluster", {**base, CLUSTER_TYPE_LABEL: "service-cluster"}),
            (
                "missing version",
                {key: value for key, value in base.items() if key != VERSION_LABEL},
            ),
            (
                "unmanaged",
                {key: value for key, value in base.items() if key != MANAGED_LABEL},
            ),
        ]
        for description, labels in cases:
            with self.subTest(description=description):
                self.assertFalse(selector_matches(selector, labels))


if __name__ == "__main__":
    unittest.main()
