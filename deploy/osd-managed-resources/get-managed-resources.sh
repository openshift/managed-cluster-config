#!/bin/bash

set -e

if [ -f  /tmp/output.log ]; then
    rm -f /tmp/output.log
fi

if [ ! $(oc whoami) ]; then
    echo "You need to be logged into a cluster to print out managed resources."
    exit 1
fi

echo "Collecting list of hive-managed resources from cluster..."

for RESOURCE in $(oc api-resources -o name | sort); do 
    oc get --ignore-not-found $RESOURCE -A -o json 2>/dev/null | jq -rc '.items[] | select(.metadata.labels["hive.openshift.io/managed"] == "true") | {kind: .kind, namespace: .metadata.namespace, name: .metadata.name}'; 
done | tee /tmp/output.log

echo "Generating configmap..."

python3 generate_configmap.py