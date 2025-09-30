#!/bin/bash

# Monitor OADP test cluster installation
CLUSTER_NAME="oadp-test-cluster"

echo "🔍 Monitoring cluster: $CLUSTER_NAME"
echo "Created: 2025-09-29T03:32:17Z"
echo "ID: 2ljqvfpi5lifjf83uedn9dcg9okoiktv"
echo ""

check_cluster() {
    echo "$(date): Checking cluster status..."
    ocm describe cluster $CLUSTER_NAME | grep -E "(State|API URL|Console URL|External ID)"
    echo ""
}

# Initial check
check_cluster

echo "💡 Installation typically takes 30-45 minutes"
echo "📊 Monitor progress at: https://cloud.redhat.com/openshift/details/s/33MAnnPhfWwDKo3TuDzpvY5vWRt#clusterHistory"
echo ""
echo "To check status manually: ocm describe cluster $CLUSTER_NAME"
echo "To login when ready: ocm cluster login $CLUSTER_NAME"