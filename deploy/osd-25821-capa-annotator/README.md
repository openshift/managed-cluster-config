# OSD-25821-capa-annotator

This contains a SelectorSyncSet config that targets `ServiceClusters` to patch `ManifestWork`s with an annotation
to run a custom version of the `capi-provider` for AWS.

## Logic

The primary logic is nested in a `CronJob` that runs periodically, enumerating clusters and deciding
if it should patch or not. This logic includes a Python script `should_patch.py` that does a `semver` comparison
to only patch clusters where the Z stream is not patched, as well as a shell script `patch.sh`.

Any cluster `>=` the patched version will _not_ be patched. In addition, the job will then remove any override annotation,
allowing the `control-plane-operator` to match the version of the cluster as normal.

The Python script is bundled in a single `ConfigMap` that is referenced across each `CronJob`.

## Making Changes to Scripts

If you make a change to either `should_patch.py` or `patch.sh`, run the included generator script to update the ConfigMap.

    ./generate_configmap.sh
    make

## Testing

The included Python script has a set of unit tests you can run to validate its logic.

``
python -m unittest tests.py
``
