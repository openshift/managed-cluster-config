#!/usr/bin/env python3

import unittest

from check_sss_selector_overlaps import (
    CLUSTER_PLATFORM_LABEL,
    MANAGED_LABEL,
    VERSION_LABEL,
    find_overlaps,
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

    def test_unresolved_template_value_is_treated_as_opaque(self):
        selector = {
            "matchExpressions": [
                {
                    "key": "api.openshift.com/id",
                    "operator": "In",
                    "values": "${{ROUTER_REPLICA_CLUSTER_IDS}}",
                }
            ]
        }
        self.assertFalse(selector_matches(selector, {}))

    def test_unknown_operator_fails(self):
        selector = {
            "matchExpressions": [
                {"key": "example.com/tier", "operator": "Equals", "values": ["osd"]}
            ]
        }
        with self.assertRaises(ValueError):
            selector_matches(selector, {"example.com/tier": "osd"})


class PatchTargetOverlapTests(unittest.TestCase):
    def test_adjacent_version_selectors_apply_to_only_one_sss(self):
        old = {
            "matchLabels": {MANAGED_LABEL: "true"},
            "matchExpressions": [
                {
                    "key": VERSION_LABEL,
                    "operator": "In",
                    "values": ["4.19", "4.20", "4.21"],
                },
                {
                    "key": CLUSTER_PLATFORM_LABEL,
                    "operator": "In",
                    "values": ["aws"],
                },
            ],
        }
        new = {
            "matchLabels": {MANAGED_LABEL: "true"},
            "matchExpressions": [
                {"key": VERSION_LABEL, "operator": "Exists"},
                {
                    "key": VERSION_LABEL,
                    "operator": "NotIn",
                    "values": ["4.19", "4.20", "4.21"],
                },
                {
                    "key": CLUSTER_PLATFORM_LABEL,
                    "operator": "In",
                    "values": ["aws"],
                },
            ],
        }
        targets = {
            ("MachineConfiguration", "openshift-machine-config-operator", "cluster"): {
                "legacy-versions": old,
                "new-versions": new,
            }
        }
        fleet = [
            {MANAGED_LABEL: "true", VERSION_LABEL: "4.21", CLUSTER_PLATFORM_LABEL: "aws"},
            {MANAGED_LABEL: "true", VERSION_LABEL: "4.22", CLUSTER_PLATFORM_LABEL: "aws"},
            {MANAGED_LABEL: "true", CLUSTER_PLATFORM_LABEL: "aws"},
        ]

        self.assertEqual([], find_overlaps(targets, fleet))

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


if __name__ == "__main__":
    unittest.main()
