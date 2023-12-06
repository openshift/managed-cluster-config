#!/bin/bash

check_ns=(
    "openshift-sre-pruning"
    "openshift-monitoring"
)

NODES=()

MACHINE_API_NAMESPACE="openshift-machine-api"

for current_ns in "${check_ns[@]}"; do
    readarray -t failedPods < <(oc -n "$current_ns" get pods -owide | grep "CreateContainerError" | awk '{print $1}')
    for pod in "${failedPods[@]}"; do
        podDescribe="$(oc -n "$current_ns" describe pod "$pod")"
        if ! echo "$podDescribe" | grep "error loading seccomp filter into kernel" >/dev/null; then
            continue
        fi
        node="$(echo "$podDescribe" | grep Node: | awk '{print $2}' | cut -d "/" -f 1)"
        if echo "${NODES[@]}" | grep "$node" >/dev/null; then
            continue
        fi
    done
done

if [ ${#NODES[@]} -eq 0 ]; then
    echo "No affected nodes."
    exit 0
fi

# print affected nodes and 

for NODE in "${NODES[@]}"; do
    nodeJson="$(oc get node "$NODE" -ojson)"

    # make sure we only restart infra nodes
    if ! jq -e '.metadata.labels."node-role.kubernetes.io/infra"' <<< "$nodeJson"; then
      echo "Found node '$node', however control-plane and worker nodes must be restarted manually"
      continue
    fi

    echo "Found node '$node'. Checking associated machine cr"

    MACHINE="$(jq -r '.metadata.annotations."machine.openshift.io/machine"' <<< "$nodeJson" )"
    if [[ $MACHINE = "" ]]; then
      echo "Couldn't find Machine for node $node. Skipping"
      continue
    fi

    echo "Found machine '$MACHINE' for node '$node'. Removing it..."
    oc -n "$MACHINE_API_NAMESPACE" delete machine "$MACHINE" --wait
    echo "Machine removed successfully. Waiting for all machines to be in Running state again"
    oc -n "$MACHINE_API_NAMESPACE" wait --all --for=jsonpath='{.status.phase}'=Running --timeout=5m machines
    echo "All Machines are running again. Waiting for all nodes to become ready."
    oc wait --all --for=condition=Ready=false --timeout=5m nodes
    echo "All nodes are Ready. Continuing."
done

# rewrite to use pull secret
osdctl servicelog post "$(oc get clusterversion version -o json | jq -r .spec.clusterID)" -t https://raw.githubusercontent.com/openshift/managed-notifications/master/osd/OCPBUGS-16655-remediation-please-upgrade.json
