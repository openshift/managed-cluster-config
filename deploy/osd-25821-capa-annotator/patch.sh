#!/bin/bash

# Required Environment Variables:
# - IMAGE
# - MAJOR_MINOR_VER
# - Z_STREAM_FIXED_VER

# Get all manifestwork objects and extract their names
managedclusters=$(oc get managedclusters -l openshiftVersion-major-minor=${MAJOR_MINOR_VER} -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# Loop through each manifestwork object
for clusterID in ${managedclusters[@]};do
  # Extract full version, namespace and name
  version=$(oc get managedclusters $clusterID -o json | jq -r '.metadata.labels.openshiftVersion')

  # Only patch the image if the clusters Z stream version is < $Z_STREAM_FIXED_VER
  # This also handles any case where the script exits non-zero for any other reason, opting to patch as a result.
  cleanup="false"
  if python /tmp/scripts/should_patch.py "${version}" "${Z_STREAM_FIXED_VER}"; then
    echo "cluster ${clusterID} does not need the override because it's Z stream is >= ${Z_STREAM_FIXED_VER}"
    echo "removing hypershift.openshift.io/capi-provider-aws-image annotation"
    cleanup="true"
  fi

  namespace=$(oc get managedclusters "$clusterID" -o json | jq -r '.metadata.labels["api.openshift.com/management-cluster"]')
  kinds=$(oc get manifestwork -n "$namespace" "$clusterID" -o json | jq -r '.spec.workload.manifests[].kind')
  num=0
  for kind in $kinds;do
    if [[ $kind == "HostedCluster" ]]; then
        echo "patching cluster: $clusterID"

        if [[ $cleanup = "true" ]]; then
          json_payload='[{"op":"remove","path":"/spec/workload/manifests/'"$num"'/metadata/annotations/hypershift.openshift.io~1capi-provider-aws-image"}]'
        else
          json_payload='[{"op":"replace","path":"/spec/workload/manifests/'"$num"'/metadata/annotations/hypershift.openshift.io~1capi-provider-aws-image","value":"'"$IMAGE"'"}]'
        fi

        echo "oc patch manifestwork $clusterID -n $namespace --type='json' -p "$json_payload""
        oc patch manifestwork "$clusterID" -n "$namespace" --type='json' -p "$json_payload"
        echo "-------------------------------------------------------------------------"
        break
    fi
  (( num++))
  done
done
