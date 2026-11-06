#!/usr/bin/env python3
"""Check generated Hive SSSes for overlapping MachineConfiguration patches."""

import argparse
from collections import defaultdict
from itertools import product
import json
from pathlib import Path
import sys

import oyaml as yaml


MANAGED_LABEL = "api.openshift.com/managed"
VERSION_LABEL = "hive.openshift.io/version-major-minor"
CLUSTER_PLATFORM_LABEL = "hive.openshift.io/cluster-platform"
PRODUCT_LABEL = "api.openshift.com/product"
FEDRAMP_LABEL = "api.openshift.com/fedramp"
CLUSTER_TYPE_LABEL = "ext-hypershift.openshift.io/cluster-type"

MAX_REPORTED_OVERLAPS = 20

BOOT_IMAGE_PATCH_TARGET = (
    "MachineConfiguration",
    "openshift-machine-config-operator",
    "cluster",
)

DEFAULT_TEMPLATE = (
    Path(__file__).resolve().parents[1]
    / "hack/00-osd-managed-cluster-config-production.yaml.tmpl"
)


def label_value(value):
    """Convert YAML scalar values to the strings used by Kubernetes labels."""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def selector_matches(selector, labels):
    """Evaluate a Kubernetes LabelSelector against a ClusterDeployment's labels."""
    selector = selector or {}
    match_labels = selector.get("matchLabels") or {}
    match_expressions = selector.get("matchExpressions") or []

    if not isinstance(match_labels, dict):
        raise ValueError("selector.matchLabels must be a mapping")
    if not isinstance(match_expressions, list):
        raise ValueError("selector.matchExpressions must be a list")

    for key, expected in match_labels.items():
        if labels.get(key) != label_value(expected):
            return False

    for expression in match_expressions:
        if not isinstance(expression, dict):
            raise ValueError("selector.matchExpressions entries must be mappings")
        key = expression.get("key")
        operator = expression.get("operator")
        values = expression.get("values") or []
        if not isinstance(values, list):
            raise ValueError(
                "selector.matchExpressions values must be a list for key %r" % key
            )
        values = {label_value(value) for value in values}
        present = key in labels
        actual = labels.get(key)

        if operator == "In":
            matched = present and actual in values
        elif operator == "NotIn":
            # Kubernetes NotIn matches when the key is absent as well as when
            # its value is not in the excluded set.
            matched = not present or actual not in values
        elif operator == "Exists":
            matched = present
        elif operator == "DoesNotExist":
            matched = not present
        else:
            raise ValueError(
                "unsupported selector operator %r for key %r" % (operator, key)
            )

        if not matched:
            return False

    return True


def synthetic_cluster_deployments():
    """Generate the requested synthetic managed-cluster label combinations."""
    versions = [None]
    versions.extend("4.%d" % minor for minor in range(41))
    versions.append("5.0")

    dimensions = (
        (VERSION_LABEL, versions),
        (CLUSTER_PLATFORM_LABEL, [None, "aws", "gcp", "azure"]),
        (PRODUCT_LABEL, [None, "osd", "rosa"]),
        (FEDRAMP_LABEL, [None, "true"]),
        (
            CLUSTER_TYPE_LABEL,
            [
                None,
                "management-cluster",
                "management-cluster-v2",
                "service-cluster",
            ],
        ),
    )

    for values in product(*(dimension_values for _, dimension_values in dimensions)):
        labels = {MANAGED_LABEL: "true"}
        for (key, _), value in zip(dimensions, values):
            if value is not None:
                labels[key] = value
        yield labels


def load_patch_targets(template_path):
    """Group generated SelectorSyncSets by patch target (kind, namespace, name)."""
    with open(template_path, "r") as stream:
        template = yaml.safe_load(stream)

    if not isinstance(template, dict) or not isinstance(template.get("objects"), list):
        raise ValueError("expected an OpenShift Template with an objects list")

    targets = defaultdict(dict)
    for obj in template["objects"]:
        if not isinstance(obj, dict) or obj.get("kind") != "SelectorSyncSet":
            continue

        metadata = obj.get("metadata") or {}
        name = metadata.get("name")
        if not name:
            raise ValueError("found SelectorSyncSet without metadata.name")

        spec = obj.get("spec") or {}
        selector = spec.get("clusterDeploymentSelector") or {}
        if not isinstance(selector, dict):
            raise ValueError(
                "SelectorSyncSet %s has an invalid clusterDeploymentSelector" % name
            )

        for patch in spec.get("patches") or []:
            if not isinstance(patch, dict):
                raise ValueError("SelectorSyncSet %s has an invalid patch" % name)
            kind = patch.get("kind")
            namespace = patch.get("namespace") or ""
            patch_name = patch.get("name")
            if not kind or not patch_name:
                raise ValueError(
                    "SelectorSyncSet %s has a patch missing kind or name" % name
                )

            target = (kind, namespace, patch_name)
            targets[target][name] = selector

    return targets


def find_overlaps(targets, cluster_deployments):
    """Return target/label/SSS tuples where a cluster matches multiple SSSes."""
    overlaps = []
    for target in sorted(targets):
        syncsets = targets[target]
        if len(syncsets) <= 1:
            continue

        for labels in cluster_deployments:
            matching_names = [
                name
                for name, selector in sorted(syncsets.items())
                if selector_matches(selector, labels)
            ]
            if len(matching_names) > 1:
                overlaps.append((target, labels, matching_names))

    return overlaps


def format_target(target):
    kind, namespace, name = target
    if namespace:
        return "%s/%s/%s" % (kind, namespace, name)
    return "%s/%s" % (kind, name)


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Fail when a synthetic ClusterDeployment matches multiple generated "
            "SelectorSyncSets patching MachineConfiguration/openshift-machine-config-operator/cluster."
        )
    )
    parser.add_argument(
        "--template-file",
        type=Path,
        default=DEFAULT_TEMPLATE,
        help="Generated Hive template to inspect (default: %(default)s)",
    )
    args = parser.parse_args()

    try:
        all_targets = load_patch_targets(args.template_file)
        if BOOT_IMAGE_PATCH_TARGET not in all_targets:
            raise ValueError(
                "generated template does not contain patch target %s"
                % format_target(BOOT_IMAGE_PATCH_TARGET)
            )
        targets = {BOOT_IMAGE_PATCH_TARGET: all_targets[BOOT_IMAGE_PATCH_TARGET]}
        deployments = list(synthetic_cluster_deployments())
        overlaps = find_overlaps(targets, deployments)
    except (OSError, ValueError, yaml.YAMLError) as error:
        print("ERROR: %s" % error, file=sys.stderr)
        return 2

    syncsets = targets[BOOT_IMAGE_PATCH_TARGET]
    print(
        "Checked %d synthetic ClusterDeployments against %d SSS(es) patching %s "
        "from %s"
        % (
            len(deployments),
            len(syncsets),
            format_target(BOOT_IMAGE_PATCH_TARGET),
            args.template_file,
        )
    )

    if overlaps:
        print("ERROR: found %d SelectorSyncSet patch-target overlaps:" % len(overlaps))
        for target, labels, names in overlaps[:MAX_REPORTED_OVERLAPS]:
            print("  Patch target: %s" % format_target(target))
            print("  ClusterDeployment labels: %s" % json.dumps(labels, sort_keys=True))
            print("  Matching SelectorSyncSets: %s" % ", ".join(names))
        if len(overlaps) > MAX_REPORTED_OVERLAPS:
            print("  ... %d more overlaps" % (len(overlaps) - MAX_REPORTED_OVERLAPS))
        return 1

    print("OK: no synthetic ClusterDeployment matches multiple SSSes for one patch target")
    return 0


if __name__ == "__main__":
    sys.exit(main())
