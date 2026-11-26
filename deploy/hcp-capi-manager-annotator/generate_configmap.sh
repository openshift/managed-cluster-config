#!/usr/bin/env bash

set -eo pipefail

echo "Generating 04-ConfigMap.yaml from files: should_patch.py, patch.sh"
oc create configmap hcp-capi-manager-annotator -n openshift-hcp-capi-manager-annotator \
  --from-file should_patch.py --from-file patch.sh --dry-run=client -o yaml > 04-ConfigMap.yaml

echo "Complete!"
