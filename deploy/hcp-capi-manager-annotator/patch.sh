#!/usr/bin/env bash

# NOTE: If you update this script, run `./generate_configmap.sh`
#
# Sets or removes hypershift.openshift.io/capi-manager-image on the
# HostedCluster inside a cluster's ManifestWork, for 4.19 and 4.20 hosted
# clusters only.
#
# The annotation is patched in place with a JSON patch so we never replace the
# whole ManifestWork: Clusters Service renders that object continuously and a
# full replace fights it (and can revert unrelated annotations).
#
# We only ever remove a value we set ourselves. If the annotation carries a
# different image, the cluster is deliberately pinned by someone else and is
# left alone.

set -uo pipefail

: "${IMAGE:?IMAGE must be set to the pinned cluster-capi-controllers image}"

ANNOTATION_KEY="hypershift.openshift.io/capi-manager-image"
ANNOTATION_POINTER="hypershift.openshift.io~1capi-manager-image"
MAX_RETRIES=3
RETRY_SLEEP=5

log() { echo "$*"; }

python_bin() {
  command -v python3 || command -v python
}

PYTHON=$(python_bin)
if [ -z "$PYTHON" ]; then
  echo "ERROR: no python interpreter found" >&2
  exit 1
fi

managed_cluster_namespace() {
  oc get managedcluster "$1" -o jsonpath='{.metadata.labels.api\.openshift\.com/management-cluster}'
}

managed_cluster_version() {
  oc get managedcluster "$1" -o jsonpath='{.metadata.labels.openshiftVersion}'
}

# patch_hostedcluster_annotation <manifestwork> <namespace> <set|remove>
patch_hostedcluster_annotation() {
  local manifestwork=$1 namespace=$2 mode=$3

  local attempt json index current has_annotations patch
  for attempt in $(seq 1 "$MAX_RETRIES"); do
    if ! json=$(oc get manifestwork "$manifestwork" -n "$namespace" -o json); then
      log "ERROR: could not read manifestwork ${namespace}/${manifestwork}"
      return 1
    fi

    index=$(jq -r '.spec.workload.manifests
      | to_entries[]
      | select(.value.kind == "HostedCluster")
      | .key' <<<"$json" | head -1)
    if [ -z "$index" ] || [ "$index" = "null" ]; then
      log "no HostedCluster manifest in ${namespace}/${manifestwork}, skipping"
      return 0
    fi

    current=$(jq -r --argjson i "$index" \
      ".spec.workload.manifests[\$i].metadata.annotations[\"${ANNOTATION_KEY}\"] // \"\"" <<<"$json")
    has_annotations=$(jq -r --argjson i "$index" \
      '.spec.workload.manifests[$i].metadata | has("annotations")' <<<"$json")

    if [ "$mode" = "set" ]; then
      if [ "$current" = "$IMAGE" ]; then
        log "${manifestwork} already pinned"
        return 0
      fi
      if [ -n "$current" ]; then
        log "${manifestwork} carries a different pin (${current}), leaving it alone"
        return 0
      fi
    else
      if [ -z "$current" ]; then
        return 0
      fi
      if [ "$current" != "$IMAGE" ]; then
        log "${manifestwork} pin is not ours (${current}), leaving it alone"
        return 0
      fi
    fi

    if [ "$mode" = "set" ]; then
      if [ "$has_annotations" = "true" ]; then
        patch=$(jq -cn --argjson i "$index" --arg v "$IMAGE" \
          '[{op: "add", path: "/spec/workload/manifests/\($i)/metadata/annotations/'"$ANNOTATION_POINTER"'", value: $v}]')
      else
        patch=$(jq -cn --argjson i "$index" --arg v "$IMAGE" \
          '[{op: "add", path: "/spec/workload/manifests/\($i)/metadata/annotations", value: {}},
            {op: "add", path: "/spec/workload/manifests/\($i)/metadata/annotations/'"$ANNOTATION_POINTER"'", value: $v}]')
      fi
    else
      patch=$(jq -cn --argjson i "$index" \
        '[{op: "remove", path: "/spec/workload/manifests/\($i)/metadata/annotations/'"$ANNOTATION_POINTER"'"}]')
    fi

    if oc patch manifestwork "$manifestwork" -n "$namespace" --type=json -p "$patch"; then
      log "${mode} ${ANNOTATION_KEY} on ${namespace}/${manifestwork}"
      return 0
    fi

    log "patch attempt ${attempt}/${MAX_RETRIES} failed on ${namespace}/${manifestwork}, retrying"
    sleep "$RETRY_SLEEP"
  done

  log "ERROR: giving up on ${namespace}/${manifestwork} after ${MAX_RETRIES} attempts"
  return 1
}

# reconcile <managedcluster> <label to select on, empty for all>
reconcile_one() {
  local cluster=$1 version namespace mode rc=0

  version=$(managed_cluster_version "$cluster")
  if [ -z "$version" ]; then
    log "skipping ${cluster}: no openshiftVersion label"
    return 0
  fi

  "$PYTHON" /tmp/scripts/should_patch.py "$version"
  case $? in
    1) mode="set" ;;
    0) mode="remove" ;;
    *) log "skipping ${cluster}: unparsable version '${version}'"; return 0 ;;
  esac

  namespace=$(managed_cluster_namespace "$cluster")
  if [ -z "$namespace" ] || [ "$namespace" = "null" ]; then
    log "skipping ${cluster}: not a hosted cluster"
    return 0
  fi

  patch_hostedcluster_annotation "$cluster" "$namespace" "$mode" || rc=1
  echo "-------------------------------------------------------------------------"
  return "$rc"
}

main() {
  local selector=${1:-}
  local clusters cluster status=0

  if [ -n "$selector" ]; then
    clusters=$(oc get managedclusters -l "$selector" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  else
    clusters=$(oc get managedclusters -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  fi

  for cluster in $clusters; do
    reconcile_one "$cluster" || status=1
  done

  return "$status"
}

main "$@"
