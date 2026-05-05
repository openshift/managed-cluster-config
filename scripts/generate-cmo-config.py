#!/usr/bin/env python

import copy
import glob
import oyaml as yaml
import os

# --- Paths ---

input_file_path = os.path.join("resources", "cluster-monitoring-config", "config.yaml")
selectors_file_path = os.path.join("resources", "cluster-monitoring-config", "selectors.yaml")
overrides_dir = os.path.join("resources", "cluster-monitoring-config", "overrides")

# Mapping from deploy directory (relative to deploy/) to output file paths.
# This preserves the exact same output structure as before.
OUTPUT_MAP = {
    "cluster-monitoring-config": os.path.join(
        "deploy", "cluster-monitoring-config",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config/pre-4.11": os.path.join(
        "deploy", "cluster-monitoring-config", "pre-4.11",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config/4.11-4.15": os.path.join(
        "deploy", "cluster-monitoring-config", "4.11-4.15",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config/management-clusters": os.path.join(
        "deploy", "cluster-monitoring-config", "management-clusters",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config-non-uwm": os.path.join(
        "deploy", "cluster-monitoring-config-non-uwm",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config-non-uwm/clusters-v4.5": os.path.join(
        "deploy", "cluster-monitoring-config-non-uwm", "clusters-v4.5",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config-non-uwm/pre-4.11": os.path.join(
        "deploy", "cluster-monitoring-config-non-uwm", "pre-4.11",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config-non-uwm/4.11-4.15": os.path.join(
        "deploy", "cluster-monitoring-config-non-uwm", "4.11-4.15",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "osd-fedramp-cluster-monitoring-config": os.path.join(
        "deploy", "osd-fedramp-cluster-monitoring-config",
        "50-GENERATED-cluster-monitoring-config.yaml"),
    "cluster-monitoring-config-non-uwm/management-clusters": os.path.join(
        "deploy", "cluster-monitoring-config-non-uwm", "management-clusters",
        "50-GENERATED-cluster-monitoring-config.yaml"),
}

# Which deploy directories belong to which "appliesTo" category.
# Used to determine where override exclusions and subdirectories go.
APPLIES_TO_MAP = {
    "uwm": [
        "cluster-monitoring-config",
        "cluster-monitoring-config/pre-4.11",
        "cluster-monitoring-config/4.11-4.15",
        "cluster-monitoring-config/management-clusters",
    ],
    "non-uwm": [
        "cluster-monitoring-config-non-uwm",
        "cluster-monitoring-config-non-uwm/clusters-v4.5",
        "cluster-monitoring-config-non-uwm/pre-4.11",
        "cluster-monitoring-config-non-uwm/4.11-4.15",
        "cluster-monitoring-config-non-uwm/management-clusters",
    ],
    "fedramp": [
        "osd-fedramp-cluster-monitoring-config",
    ],
}

# The dump parameters for each deploy directory (preserves existing behavior).
# Format: (enableUserWorkload, disableremoteWrite, retentionTime, enableGrafana, keepPrometheusAdapter)
DUMP_PARAMS = {
    "cluster-monitoring-config":                          (True,  False, "11d", False, False),
    "cluster-monitoring-config/pre-4.11":                 (True,  False, "7d",  True,  True),
    "cluster-monitoring-config/4.11-4.15":                (True,  False, "7d",  True,  True),
    "cluster-monitoring-config/management-clusters":      (True,  False, "7d",  False, False),
    "cluster-monitoring-config-non-uwm":                  (False, False, "11d", False, False),
    "cluster-monitoring-config-non-uwm/clusters-v4.5":    (False, False, "11d", True,  True),
    "cluster-monitoring-config-non-uwm/pre-4.11":         (False, False, "7d",  True,  True),
    "cluster-monitoring-config-non-uwm/4.11-4.15":        (False, False, "7d",  True,  True),
    "osd-fedramp-cluster-monitoring-config":               (True,  True,  "11d", False, False),
    "cluster-monitoring-config-non-uwm/management-clusters": (False, False, "7d", False, False),
}

# Target label keys for override targeting
TARGET_LABEL_KEYS = {
    "cluster": "api.openshift.com/id",
    "organization": "api.openshift.com/legal-entity-id",
}


# --- YAML Helpers ---

def str_presenter(dumper, data):
    if len(data.splitlines()) > 1:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)

yaml.add_representer(str, str_presenter)


def deep_merge(base, overrides):
    """Deep merge overrides into base dict. Returns a new dict."""
    result = copy.deepcopy(base)
    for key, value in overrides.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


# --- Core Functions ---

def dump_configmap(input_path, configmap_path, enableUserWorkload,
                   disableremoteWrite, retentionTime="11d",
                   enableGrafana=False,
                   keepPrometheusAdapter=False,
                   configOverrides=None):
    with open(input_path, 'r') as input_file:
        config = yaml.safe_load(input_file)
        config["enableUserWorkload"] = enableUserWorkload
        config["prometheusK8s"]["retention"] = retentionTime
        if disableremoteWrite:
            del config['prometheusK8s']['remoteWrite']

        if enableGrafana:
            config["grafana"] = copy.deepcopy(config["prometheusOperator"])

        if not keepPrometheusAdapter:
            del config['k8sPrometheusAdapter']

        # Apply config overrides (deep merge) if provided
        if configOverrides:
            config = deep_merge(config, configOverrides)

        cmo_config = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {
                "name": "cluster-monitoring-config",
                "namespace": "openshift-monitoring"
            },
            "data": {
                "config.yaml": yaml.dump(config)
            }
        }

        os.makedirs(os.path.dirname(configmap_path), exist_ok=True)
        with open(configmap_path, 'w') as outfile:
            yaml.dump(cmo_config, outfile)


def load_overrides():
    """Load all override definitions from the overrides directory."""
    overrides = []
    pattern = os.path.join(overrides_dir, "*.yaml")
    for filepath in sorted(glob.glob(pattern)):
        with open(filepath, 'r') as f:
            override = yaml.safe_load(f)
        if override is None:
            continue
        # Validate required fields
        for field in ("name", "appliesTo", "target", "configOverrides"):
            if field not in override:
                raise ValueError(f"Override file {filepath} missing required field: {field}")
        if override["target"]["type"] not in TARGET_LABEL_KEYS:
            raise ValueError(
                f"Override file {filepath} has invalid target type: {override['target']['type']}. "
                f"Must be one of: {list(TARGET_LABEL_KEYS.keys())}")
        if override["appliesTo"] not in list(APPLIES_TO_MAP.keys()) + ["both"]:
            raise ValueError(
                f"Override file {filepath} has invalid appliesTo: {override['appliesTo']}. "
                f"Must be one of: {list(APPLIES_TO_MAP.keys()) + ['both']}")
        overrides.append(override)
    return overrides


def get_affected_deploy_dirs(override):
    """Return the list of deploy directory keys affected by an override."""
    applies_to = override["appliesTo"]
    if applies_to == "both":
        return APPLIES_TO_MAP["uwm"] + APPLIES_TO_MAP["non-uwm"]
    return APPLIES_TO_MAP[applies_to]


def build_exclusion_expression(override):
    """Build a NotIn matchExpression for excluding override targets from defaults."""
    label_key = TARGET_LABEL_KEYS[override["target"]["type"]]
    values = override["target"]["values"]
    return {
        "key": label_key,
        "operator": "NotIn",
        "values": values,
    }


def build_inclusion_expression(override):
    """Build an In matchExpression for targeting override clusters."""
    label_key = TARGET_LABEL_KEYS[override["target"]["type"]]
    values = override["target"]["values"]
    return {
        "key": label_key,
        "operator": "In",
        "values": values,
    }


def generate_selector_configs(selectors, overrides):
    """Generate config.yaml files for all deploy directories, with override exclusions."""
    for deploy_dir, selector in selectors.items():
        selector_with_exclusions = copy.deepcopy(selector)

        # Add NotIn exclusions for each override that affects this deploy dir
        for override in overrides:
            affected_dirs = get_affected_deploy_dirs(override)
            if deploy_dir in affected_dirs:
                exclusion = build_exclusion_expression(override)
                selector_with_exclusions["selectorSyncSet"]["matchExpressions"].append(exclusion)

        # Write the config.yaml
        config_path = os.path.join("deploy", deploy_dir, "config.yaml")
        os.makedirs(os.path.dirname(config_path), exist_ok=True)
        with open(config_path, 'w') as f:
            yaml.dump(selector_with_exclusions, f, default_flow_style=False)


def generate_override_outputs(selectors, overrides):
    """Generate override subdirectories with config.yaml and ConfigMap."""
    for override in overrides:
        affected_dirs = get_affected_deploy_dirs(override)
        override_name = override["name"]
        config_overrides = override.get("configOverrides", {})

        for deploy_dir in affected_dirs:
            # Determine the override subdirectory path
            override_subdir = os.path.join("deploy", deploy_dir, f"override-{override_name}")

            # --- Generate config.yaml with In selector ---
            # Start from the base selector for this deploy dir, then replace/add
            # the override targeting expression
            base_selector = copy.deepcopy(selectors[deploy_dir])
            override_selector = copy.deepcopy(base_selector)
            # Add the In expression for the override target
            override_selector["selectorSyncSet"]["matchExpressions"].append(
                build_inclusion_expression(override)
            )

            config_path = os.path.join(override_subdir, "config.yaml")
            os.makedirs(override_subdir, exist_ok=True)
            with open(config_path, 'w') as f:
                yaml.dump(override_selector, f, default_flow_style=False)

            # --- Generate the ConfigMap with merged overrides ---
            params = DUMP_PARAMS[deploy_dir]
            configmap_path = os.path.join(
                override_subdir, "50-GENERATED-cluster-monitoring-config.yaml")

            dump_configmap(
                input_file_path, configmap_path,
                enableUserWorkload=params[0],
                disableremoteWrite=params[1],
                retentionTime=params[2],
                enableGrafana=params[3],
                keepPrometheusAdapter=params[4],
                configOverrides=config_overrides,
            )


# --- Main ---

def main():
    # Load base selectors
    with open(selectors_file_path, 'r') as f:
        selectors = yaml.safe_load(f)

    # Load overrides
    overrides = load_overrides()

    # 1. Generate all default ConfigMaps (unchanged behavior)
    for deploy_dir, output_path in OUTPUT_MAP.items():
        params = DUMP_PARAMS[deploy_dir]
        dump_configmap(
            input_file_path, output_path,
            enableUserWorkload=params[0],
            disableremoteWrite=params[1],
            retentionTime=params[2],
            enableGrafana=params[3],
            keepPrometheusAdapter=params[4],
        )

    # 2. Generate config.yaml files with override exclusions
    generate_selector_configs(selectors, overrides)

    # 3. Generate override subdirectories
    generate_override_outputs(selectors, overrides)

    if overrides:
        print(f"Generated {len(overrides)} override(s):")
        for o in overrides:
            affected = get_affected_deploy_dirs(o)
            print(f"  - {o['name']} ({o['target']['type']}: {o['target']['values']}) "
                  f"-> {len(affected)} deploy dir(s)")
    else:
        print("No overrides found.")


if __name__ == "__main__":
    main()
