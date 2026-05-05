#!/usr/bin/env python
"""Generate cluster-monitoring-config ConfigMaps and SelectorSyncSet configs.

All variant definitions live in resources/cluster-monitoring-config/variants/*.yaml.
Each file is self-contained: it carries its selector (which clusters it targets) and
its config transformations (what monitoring config those clusters get).

There are two kinds of variants:
  - Base variants: have a "selector" field. They define the default config for a
    class of clusters (e.g. UWM 4.16+, non-UWM pre-4.11, FedRAMP).
  - Override variants: have a "parent" and "target" field. They specialize a base
    variant for specific clusters or organizations. The script automatically adds
    a NotIn exclusion on the parent's selector so targeted clusters don't receive
    two conflicting configs.
"""

import copy
import glob
import oyaml as yaml
import os

# --- Paths ---

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES_DIR = os.path.join(BASE_DIR, "resources", "cluster-monitoring-config")
DEPLOY_DIR = os.path.join(BASE_DIR, "deploy")
INPUT_FILE_PATH = os.path.join(RESOURCES_DIR, "config.yaml")
VARIANTS_DIR = os.path.join(RESOURCES_DIR, "variants")

# Label keys used for cluster/org targeting
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


def remove_dotted_key(config, dotted_key):
    """Remove a key from a nested dict using a dotted path like 'a.b.c'."""
    parts = dotted_key.split(".")
    obj = config
    for part in parts[:-1]:
        if part not in obj or not isinstance(obj[part], dict):
            return
        obj = obj[part]
    obj.pop(parts[-1], None)


# --- Loading ---

def load_base_config():
    """Load the base monitoring config."""
    with open(INPUT_FILE_PATH, 'r') as f:
        return yaml.safe_load(f)


def load_variants():
    """Load all variant definitions from the variants directory.

    Returns (base_variants, override_variants) where:
      - base_variants: list of variants with a 'selector' (no 'target')
      - override_variants: list of variants with a 'parent' and 'target'
    """
    base_variants = []
    override_variants = []
    pattern = os.path.join(VARIANTS_DIR, "*.yaml")

    for filepath in sorted(glob.glob(pattern)):
        with open(filepath, 'r') as f:
            variant = yaml.safe_load(f)
        if variant is None:
            continue

        variant["_source"] = os.path.basename(filepath)

        if "target" in variant:
            # Override variant
            for field in ("parent", "target"):
                if field not in variant:
                    raise ValueError(
                        f"{filepath}: override variant missing required field '{field}'")
            target = variant["target"]
            if target["type"] not in TARGET_LABEL_KEYS:
                raise ValueError(
                    f"{filepath}: invalid target type '{target['type']}'. "
                    f"Must be one of: {list(TARGET_LABEL_KEYS.keys())}")
            if "values" not in target:
                raise ValueError(f"{filepath}: target missing 'values'")
            if not variant.get("configOverrides") and not variant.get("removeKeys") and not variant.get("copyKeys"):
                raise ValueError(
                    f"{filepath}: override must specify at least one of: "
                    f"configOverrides, removeKeys, copyKeys")
            override_variants.append(variant)
        else:
            # Base variant
            for field in ("deployDir", "selector"):
                if field not in variant:
                    raise ValueError(
                        f"{filepath}: base variant missing required field '{field}'")
            base_variants.append(variant)

    return base_variants, override_variants


# --- Config Building ---

def apply_transformations(config, variant):
    """Apply configOverrides, copyKeys, and removeKeys from a variant definition."""
    # 1. Deep-merge configOverrides
    overrides = variant.get("configOverrides")
    if overrides:
        config = deep_merge(config, overrides)

    # 2. Apply copyKeys (e.g., grafana: prometheusOperator)
    for dest, src in variant.get("copyKeys", {}).items():
        if src in config:
            config[dest] = copy.deepcopy(config[src])

    # 3. Apply removeKeys
    for key in variant.get("removeKeys", []):
        remove_dotted_key(config, key)

    return config


def build_configmap(config):
    """Wrap a monitoring config dict into a ConfigMap YAML structure."""
    return {
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


def write_yaml(data, output_path):
    """Write a YAML structure to a file, creating directories as needed."""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)


# --- Generation ---

def generate(base_config, base_variants, override_variants):
    """Generate all outputs: ConfigMaps and config.yaml files."""

    # Index base variants by deployDir for parent lookups
    base_by_dir = {}
    for v in base_variants:
        base_by_dir[v["deployDir"]] = v

    # Collect overrides grouped by parent deployDir
    overrides_by_parent = {}
    for ov in override_variants:
        parent_dir = ov["parent"]
        if parent_dir not in base_by_dir:
            raise ValueError(
                f"{ov['_source']}: parent '{parent_dir}' not found. "
                f"Available: {list(base_by_dir.keys())}")
        overrides_by_parent.setdefault(parent_dir, []).append(ov)

    # --- Generate base variants ---
    for variant in base_variants:
        deploy_dir = variant["deployDir"]
        variant_config = apply_transformations(copy.deepcopy(base_config), variant)

        # Write ConfigMap
        configmap_path = os.path.join(
            DEPLOY_DIR, deploy_dir, "50-GENERATED-cluster-monitoring-config.yaml")
        write_yaml(build_configmap(variant_config), configmap_path)

        # Build selector with NotIn exclusions for any overrides targeting this variant
        selector = copy.deepcopy(variant["selector"])
        for ov in overrides_by_parent.get(deploy_dir, []):
            target = ov["target"]
            selector["selectorSyncSet"]["matchExpressions"].append({
                "key": TARGET_LABEL_KEYS[target["type"]],
                "operator": "NotIn",
                "values": target["values"],
            })

        config_path = os.path.join(DEPLOY_DIR, deploy_dir, "config.yaml")
        write_yaml(selector, config_path)

    # --- Generate override variants ---
    for ov in override_variants:
        parent_dir = ov["parent"]
        parent = base_by_dir[parent_dir]
        target = ov["target"]

        # Derive the deploy subdirectory name from the override filename
        override_name = ov["_source"].replace(".yaml", "")
        override_dir = os.path.join(parent_dir, f"override-{override_name}")

        # Build config: base -> parent transformations -> override transformations
        config = apply_transformations(copy.deepcopy(base_config), parent)
        config = apply_transformations(config, ov)

        # Write ConfigMap
        configmap_path = os.path.join(
            DEPLOY_DIR, override_dir, "50-GENERATED-cluster-monitoring-config.yaml")
        write_yaml(build_configmap(config), configmap_path)

        # Write config.yaml: parent's selector + In for the targeted clusters
        selector = copy.deepcopy(parent["selector"])
        selector["selectorSyncSet"]["matchExpressions"].append({
            "key": TARGET_LABEL_KEYS[target["type"]],
            "operator": "In",
            "values": target["values"],
        })

        config_path = os.path.join(DEPLOY_DIR, override_dir, "config.yaml")
        write_yaml(selector, config_path)

    return base_variants, override_variants


# --- Main ---

def main():
    base_config = load_base_config()
    base_variants, override_variants = load_variants()

    generate(base_config, base_variants, override_variants)

    print(f"Generated {len(base_variants)} base variant(s):")
    for v in base_variants:
        n_overrides = len([ov for ov in override_variants if ov["parent"] == v["deployDir"]])
        suffix = f" ({n_overrides} override(s))" if n_overrides else ""
        print(f"  - {v['deployDir']}{suffix}")

    if override_variants:
        print(f"Generated {len(override_variants)} override(s):")
        for ov in override_variants:
            print(f"  - {ov['_source']} -> {ov['parent']}")


if __name__ == "__main__":
    main()
