#!/usr/bin/env bash

# NOTE: If you update this script, run `./generate_configmap.sh`

# Required Environment Variables:
# - IMAGE
# - MAJOR_MINOR_VER
# - Z_STREAM_FIXED_VER

# Ensure we have python available before running further logic
if ! command -v python &>/dev/null; then
  echo "ERROR: python not found, required for this script to run"
  exit 1
fi

MAX_RETRIES=3

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

  # If the managedcluster does not have a api.openshift.io/management-cluster label, then it should be skipped. This is
  # usually because the local cluster + service cluster are registered as "managedcluster"s.
  if [ "$namespace" == "null" ] || [ "$namespace" == "" ]; then
    echo "skipping cluster $clusterID because it is a management or local cluster"
    continue
  fi

  echo "patching cluster: $clusterID"

  # Atomic read-modify-write with retry to avoid racing on manifest array indices.
  # Reads the full ManifestWork, transforms via jq (by kind, not index), and replaces.
  # oc replace fails on resourceVersion conflict, so we retry.
  for attempt in $(seq 1 $MAX_RETRIES); do
    if [[ $cleanup == "true" ]]; then
      modified=$(oc get manifestwork "$clusterID" -n "$namespace" -o json | jq '
        .spec.workload.manifests |= map(
          if .kind == "HostedCluster" then
            del(.metadata.annotations["hypershift.openshift.io/capi-provider-aws-image"])
          else . end
        )
      ')
    else
      modified=$(oc get manifestwork "$clusterID" -n "$namespace" -o json | jq --arg image "$IMAGE" '
        .spec.workload.manifests |= map(
          if .kind == "HostedCluster" then
            .metadata.annotations["hypershift.openshift.io/capi-provider-aws-image"] = $image
          else . end
        )
      ')
    fi

    replace_output=$(echo "$modified" | oc replace -f - 2>&1)
    replace_rc=$?

    if [[ $replace_rc -eq 0 ]]; then
      echo "successfully patched cluster $clusterID"
      break
    fi

    if echo "$replace_output" | grep -qi "conflict\|the object has been modified"; then
      echo "conflict on attempt $attempt/$MAX_RETRIES for cluster $clusterID, retrying..."
    else
      echo "ERROR: failed to replace manifestwork for cluster $clusterID: $replace_output"
      exit 1
    fi
  done

  if [[ $replace_rc -ne 0 ]]; then
    echo "ERROR: failed to patch cluster $clusterID after $MAX_RETRIES attempts: $replace_output"
    exit 1
  fi

  echo "-------------------------------------------------------------------------"
done
