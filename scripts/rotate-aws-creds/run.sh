#!/bin/bash
set -euo pipefail

ENVIRONMENT=${1:-}
CLUSTER_NAME=${2:-}
if [[ $ENVIRONMENT == "" || $CLUSTER_NAME == "" ]]; then
    echo "Usage: $0 <environment> <cluster name> "
    exit 1
fi

CLUSTER_ID=$(ocm list clusters | grep "$CLUSTER_NAME" | awk '{print $1}')
if [[ "$CLUSTER_ID" == "" ]]; then
    echo "Cluster ID for $CLUSTER_NAME could not be found"
    exit 1
fi

SHARD_NAME=$(ocm get "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}/provision_shard" | jq -r '.aws_account_operator_config.server' | cut -d '.' -f2)

if [[ "$SHARD_NAME" == "hive-stage" || "$SHARD_NAME" == "hive-production" ]]; then
    exec "$(dirname "$0")/v3.sh" "$ENVIRONMENT" "$CLUSTER_ID"
else
    exec "$(dirname "$0")/sharded.sh" "$CLUSTER_ID" "$SHARD_NAME"
fi
