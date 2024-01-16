#!/bin/bash

set -euo pipefail

CHECKED_NAMESPACES=(
    "openshift-sre-pruning"
    "openshift-monitoring"
)

LAST_SL_CONFIGMAP="ocpbugs-15043-last-sl-sent"
LAST_RUN_ANNOTATION="lasttimestamp"
DELAY_BETWEEN_SEND_SECONDS="86400"

NODES=()

MACHINE_API_NAMESPACE="openshift-machine-api"

for current_ns in "${CHECKED_NAMESPACES[@]}"; do
    readarray -t failedPods < <(oc -n "$current_ns" get pods -owide | grep "CreateContainerError" | awk '{print $1}')
    for pod in "${failedPods[@]}"; do
        echo "Found pod $pod failing."
        podDescribe="$(oc -n "$current_ns" describe pod "$pod")"

        if ! echo "$podDescribe" | grep "error loading seccomp filter into kernel" >/dev/null; then
            echo -e "\t$pod is failing for another reason. Ignoring"
            continue
        fi

        node="$(echo "$podDescribe" | grep Node: | awk '{print $2}' | cut -d "/" -f 1)"
        echo -e "\t$pod on $node having seccomp issues"
        if echo "${NODES[@]}" | grep "$node" >/dev/null; then
            continue
        fi
        NODES+=("$node")
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
    if ! jq -e '.metadata.labels."node-role.kubernetes.io/infra"' <<< "$nodeJson" > /dev/null ; then
      echo "Found node '$node', however control-plane and worker nodes must be restarted manually"
      continue
    fi

    echo "Found node '$node'. Checking associated machine cr"

    MACHINE="$(jq -r '.metadata.annotations."machine.openshift.io/machine"' <<< "$nodeJson" | cut -d '/' -f2)"
    if [[ $MACHINE = "" ]]; then
      echo "Couldn't find Machine for node $node. Skipping"
      continue
    fi

    echo "Found machine '$MACHINE' for node '$node'. Removing it..."
    oc -n "$MACHINE_API_NAMESPACE" delete machine "$MACHINE" --wait
    echo "Machine removed successfully. Waiting for all machines to be in Running state again"
    oc -n "$MACHINE_API_NAMESPACE" wait --all --for=jsonpath='{.status.phase}'=Running --timeout=5m machines
    echo "All Machines are running again. Waiting for all nodes to become ready."
    oc wait --all --for=condition=Ready=true --timeout=5m nodes
    echo "All nodes are Ready. Continuing."
done


currentTimestamp=$(date -u +%s)

if oc get cm "$LAST_SL_CONFIGMAP" > /dev/null; then 
  if oc get cm "$LAST_SL_CONFIGMAP" -ojson | jq -e ".metadata.annotations.$LAST_RUN_ANNOTATION" > /dev/null; then
    lastSentTimestamp=$(oc get cm "$LAST_SL_CONFIGMAP" -ojson | jq -r ".metadata.annotations.$LAST_RUN_ANNOTATION")
    if [[ $(( currentTimestamp - lastSentTimestamp )) -lt $DELAY_BETWEEN_SEND_SECONDS ]]; then 
      echo "An SL was already sent recently. Skipping it this time."
      exit 0
    fi
  fi
fi

echo "Retrieving pull secret"
SECRET=$(oc -n openshift-config get secret pull-secret -ojson | jq -r '.data.".dockerconfigjson" | @base64d ' | jq -r '.auths."cloud.openshift.com".auth')
echo "Pull secret retrieved"

echo "Retrieving cluster uuid"
EXTERNAL_CLUSTER_ID=$( oc get clusterversion version -o json | jq -r '.spec.clusterID' )
echo "Cluster UUID is: $EXTERNAL_CLUSTER_ID"

echo "Getting OCM Base Url"
OAO_CONFIGMAP="ocm-agent-cm"
OAO_NAMESPACE="openshift-ocm-agent-operator"

MUO_CONFIGMAP="managed-upgrade-operator-config"
MUO_NAMESPACE="openshift-managed-upgrade-operator"
if oc get configmap -n "$OAO_NAMESPACE" "$OAO_CONFIGMAP"; then
  OCM_BASE_URL=$(oc get configmap -n "$OAO_NAMESPACE" "$OAO_CONFIGMAP" -o json | jq -r '.data.ocmBaseURL')
elif oc get configmap -n "$MUO_NAMESPACE" "$MUO_CONFIGMAP"; then
  OCM_BASE_URL=$(oc get configmap -n "$MUO_NAMESPACE" "$MUO_CONFIGMAP" -o json | jq -r '.data."config.yaml"' | grep ocmBaseUrl | awk '{print $2;}')
else 
  echo "Couldn't determin OCM BASE URL. Won't send a servicelog"
fi
echo "OCM Base URL is: $OCM_BASE_URL"


SL_URL="${OCM_BASE_URL}/api/service_logs/v1/cluster_logs"


SL_POST_DATA=$(cat << EOF
{
  "cluster_uuid": "$EXTERNAL_CLUSTER_ID",
  "severity": "Warning",
  "service_name": "SREManualAction",
  "summary": "Cluster impacted by OCPBUGS-16655, upgrade recommended",
  "description": "Your cluster is impacted by https://issues.redhat.com/browse/OCPBUGS-16655, which results in nodes periodically being unable to run containers. Red Hat SRE has responded to and temporarily remediated impacts of this bug on this cluster and recommends that the cluster be upgraded to 4.13.10 or later as soon as convenient.",
  "internal_only": false,
  "_tags": [
    "sop_PruningCronjobErrorSRE"
  ]
}
EOF
)

echo "SENDING SL: $SL_POST_DATA"

curl -v -m 20 -X POST \
  -d "$SL_POST_DATA" \
  -H "Content-Type: application/json" \
  -H "Authorization: AccessToken $EXTERNAL_CLUSTER_ID:$SECRET" "$SL_URL"

echo "Annotation configmap with timestamp"

oc create configmap "$LAST_SL_CONFIGMAP" || true
oc annotate configmap --overwrite "$LAST_SL_CONFIGMAP" "${LAST_RUN_ANNOTATION}=${currentTimestamp}"
