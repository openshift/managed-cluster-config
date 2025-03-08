#!/bin/bash

# Required Environment Variables:
# - IMAGE
# - MAJOR_MINOR_VER
# - Z_STREAM_FIXED_VER

# Get all manifestwork objects and extract their names
managedclusters=$(oc get managedclusters -l openshiftVersion-major-minor=${MAJOR_MINOR_VER} -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# Loop through each manifestwork object
for clusterID in ${managedclusters[@]};do
  # Clean up annotation due to upgrade bug in OCPBUGS-52819
  # Removing annotation for all versions as kube apiserver arguments prevent control plane operator image from comming up
  # after upgrade has started, this causes pods to crashloop see incident #itn-2025-00060

  namespace=$(oc get managedclusters "$clusterID" -o json | jq -r '.metadata.labels["api.openshift.com/management-cluster"]')
  kinds=$(oc get manifestwork -n "$namespace" "$clusterID" -o json | jq -r '.spec.workload.manifests[].kind')
  num=0
  for kind in $kinds;do
    if [[ $kind == "HostedCluster" ]]; then
        echo "removing annotation for cluster: $clusterID"

        json_payload='[{"op":"remove","path":"/spec/workload/manifests/'"$num"'/metadata/annotations/hypershift.openshift.io~1control-plane-operator-image"}]'

        echo "oc patch manifestwork $clusterID -n $namespace --type='json' -p "$json_payload""
        oc patch manifestwork "$clusterID" -n "$namespace" --type='json' -p "$json_payload"
        echo "-------------------------------------------------------------------------"
        break
    fi
  (( num++))
  done
done
