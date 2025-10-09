# SREP-2019 HCP CVO Pinning

This contains a SelectorSyncSet config that targets HyperShift `ServiceClusters` to patch `ManifestWork` objects with an annotation to override the cluster-version-operator image for specific cluster versions.

## Logic

The primary logic is contained in a `CronJob` that runs periodically (every 5 minutes), enumerating all managed clusters and deciding whether to add or remove CVO image override annotations.

### Components

- **cvo_pinner.py**: A Python script that:
  - Loads version-to-image mappings from `version-mappings.yaml`
  - Iterates over all managed clusters
  - For clusters with versions listed in the mappings, adds the `hypershift.openshift.io/image-overrides` annotation
  - For clusters with versions NOT in the mappings, removes any existing override annotation
  - Includes comprehensive logging and error handling
  - Accepts command-line argument `--mappings-file` to specify a custom path to the mappings file

  **Usage:**
  ```bash
  cvo_pinner.py [--mappings-file PATH] [--dry-run]

  # Examples:
  # Run with default mappings file
  cvo_pinner.py

  # Run with custom mappings file
  cvo_pinner.py --mappings-file /path/to/mappings.yaml

  # Dry-run mode (no changes made, shows what would be done)
  cvo_pinner.py --dry-run
  ```

- **version-mappings.yaml**: A YAML file defining which cluster versions should have CVO image overrides:
  ```yaml
  mappings:
    - version: "4.18.23"
      image: "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:938c5d1f69c38295bb20659528c8dee1b62ad5a256a491c730ad61d12bbf29ad"
    - version: "4.18.24"
      image: "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:938c5d1f69c38295bb20659528c8dee1b62ad5a256a491c730ad61d12bbf29ad"
  ```

- **ConfigMap**: Bundles both `cvo_pinner.py` and `version-mappings.yaml` for use by the CronJob

- **CronJob**: Runs the Python script every 5 minutes on service clusters

### Annotation Format

The script uses the `hypershift.openshift.io/image-overrides` annotation with the value format:
```
cluster-version-operator=<image>
```

For example:
```
hypershift.openshift.io/image-overrides=cluster-version-operator=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:abc123
```

## Making Changes

### Updating Version Mappings

To add or remove version overrides, edit `version-mappings.yaml` and then regenerate the ConfigMap:

```bash
./generate_configmap.sh
make
```

### Modifying the Script

If you make changes to `cvo_pinner.py`, run the included generator script to update the ConfigMap:

```bash
./generate_configmap.sh
make
```

## Testing

### Unit Tests

The included Python script has unit tests you can run to validate the logic:

```bash
python -m unittest test_cvo_pinner.py
```

### Dry-Run Testing

Before deploying changes, you can test the script in dry-run mode to see what it would do without making actual changes:

```bash
# Test with current version mappings
cvo_pinner.py --dry-run

# Test with a custom mappings file
cvo_pinner.py --mappings-file /path/to/test-mappings.yaml --dry-run
```

In dry-run mode, the script will:
- Read all managed clusters
- Evaluate which clusters would be patched or have annotations removed
- Log the exact `oc patch` commands that would be executed
- NOT make any actual changes to the cluster

## Deployment

This configuration targets HyperShift service clusters (non-FedRAMP) via the SelectorSyncSet defined in `config.yaml`:
- `ext-hypershift.openshift.io/cluster-type: service-cluster`
- `api.openshift.com/fedramp: NotIn [true]`

The CronJob runs with appropriate RBAC permissions to read managed clusters and patch manifestwork objects.
