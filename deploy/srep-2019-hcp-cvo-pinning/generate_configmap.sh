#!/usr/bin/env bash

set -eo pipefail

echo "Generating 04-ConfigMap.yaml from files: cvo_pinner.py, version-mappings.yaml"
oc create configmap hcp-cvo-pinner -n openshift-hcp-cvo-pinning \
  --from-file cvo_pinner.py --from-file version-mappings.yaml --dry-run=client -o yaml > 04-ConfigMap.yaml

echo "Complete!"
