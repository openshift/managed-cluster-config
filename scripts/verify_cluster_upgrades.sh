#!/bin/bash

IFS='
'

for cluster in "$@"
do
  echo -e "\n======================================="
  echo "verifying $cluster"
  echo "======================================="
  ocm cluster login "$cluster"%
  if ! [ $? = 0 ]
  then
    echo "error logging into cluster: $cluster skipping.."
    continue
  else
    echo -e "\n$cluster login successful, checking upgrade status\n"
  fi
  CONTROL_PLANE_STATUS=$(oc get clusterversion version -o json | jq -r '.status.conditions[] | select(.status == "True") | select(.type != "RetrievedUpdates") | .message')

  echo "======================================="
  echo "$cluster upgrade status"
  echo -e "=======================================\n"
  
  if echo "$CONTROL_PLANE_STATUS" | grep -q -E "Done applying 4\.[0-9]+\.[0-9]+"
  then
    echo "$cluster control plane status: $CONTROL_PLANE_STATUS"
  echo
    echo "$cluster control plane not ready yet!"
    echo "$CONTROL_PLANE_STATUS"
  fi

  NODE_STATUS=$(oc get nodes --no-headers)
  NODE_READY_COUNT=$(echo "$NODE_STATUS" | awk '{print $2}' | uniq | wc -l)
  if [ "$NODE_READY_COUNT" = 1 ]
  then
    NODE_STATE=$(echo "$NODE_STATUS" | awk '{print $2}' | uniq)
    if [ "$NODE_STATE" = "Ready" ]
    then
      echo "$cluster nodes state: Ready"
    fi
  else
    echo "$cluster nodes are not all ready yet"
    echo "$NODE_STATE"  
  fi

  NODE_VERSION_COUNT=$(echo "$NODE_STATUS" | awk '{print $5}' | uniq | wc -l)
  if [ "$NODE_VERSION_COUNT" = 1 ]
  NODE_VERSION=$(echo "$NODE_STATUS" | awk '{print $5}' | uniq)
  then
    echo "$cluster nodes all at version: $NODE_VERSION"
  else
    echo "$cluster nodes are not all at the same version"
    echo "$NODE_VERSION" 
  fi
  echo -e "\n=======================================\n"
done
