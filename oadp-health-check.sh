#!/bin/bash
# OADP Health Check Script
# Usage: ./oadp-health-check.sh [cluster-id]
# If no cluster-id provided, uses current cluster context

CLUSTER_ID=${1:-"current"}

echo "🔍 OADP Health Check for cluster: $CLUSTER_ID"
echo "=============================================="

# If cluster ID provided, login first
if [ "$CLUSTER_ID" != "current" ]; then
    echo "🔐 Logging into cluster $CLUSTER_ID..."
    ocm cluster login $CLUSTER_ID || {
        echo "❌ Failed to login to cluster $CLUSTER_ID"
        exit 1
    }
fi

echo ""
echo "📦 OADP Operator Status:"
CSV_STATUS=$(oc get csv -n openshift-adp 2>/dev/null | grep oadp)
if [ -n "$CSV_STATUS" ]; then
    echo "$CSV_STATUS"
    if echo "$CSV_STATUS" | grep -q "Succeeded"; then
        echo "✅ OADP operator is healthy"
    else
        echo "⚠️  OADP operator not in Succeeded state"
    fi
else
    echo "❌ OADP operator not found"
fi

echo ""
echo "🏃 OADP Pods:"
PODS=$(oc get pods -n openshift-adp 2>/dev/null)
if [ -n "$PODS" ]; then
    echo "$PODS"
    if echo "$PODS" | grep -q "Running"; then
        echo "✅ OADP pods are running"
    else
        echo "⚠️  OADP pods not running properly"
    fi
else
    echo "❌ No OADP pods found"
fi

echo ""
echo "📋 OADP Resources:"
echo "Subscriptions:"
oc get subscription -n openshift-adp 2>/dev/null || echo "❌ No subscriptions found"
echo ""
echo "DataProtectionApplications:"
oc get dpa -n openshift-adp 2>/dev/null || echo "❌ No DPA found"
echo ""
echo "Backup Schedules:"
oc get schedule -n openshift-adp 2>/dev/null || echo "❌ No schedules found"

echo ""
echo "💾 Recent Backups:"
BACKUPS=$(oc get backup -n openshift-adp --sort-by=.metadata.creationTimestamp 2>/dev/null)
if [ -n "$BACKUPS" ]; then
    echo "$BACKUPS" | tail -5
else
    echo "❌ No backups found"
fi

echo ""
echo "🔧 Environment Variable Check:"
DPA_BUCKET=$(oc get dpa -n openshift-adp -o yaml 2>/dev/null | grep "bucket:" | head -1)
if [ -n "$DPA_BUCKET" ]; then
    echo "$DPA_BUCKET"
    if echo "$DPA_BUCKET" | grep -q "\${"; then
        echo "⚠️  Environment variables not resolved"
    else
        echo "✅ Environment variables resolved"
    fi
else
    echo "❌ Cannot check DPA bucket configuration"
fi

echo ""
echo "🚨 Conflict Check (MVO vs OADP):"
MVO_PODS=$(oc get pods -n openshift-velero 2>/dev/null | grep -v "NAME")
OADP_PODS=$(oc get pods -n openshift-adp 2>/dev/null | grep -v "NAME")

if [ -n "$MVO_PODS" ] && [ -n "$OADP_PODS" ]; then
    echo "✅ Both MVO and OADP running (migration phase)"
elif [ -n "$OADP_PODS" ] && [ -z "$MVO_PODS" ]; then
    echo "✅ OADP only (migration complete)"
elif [ -n "$MVO_PODS" ] && [ -z "$OADP_PODS" ]; then
    echo "⚠️  MVO only (OADP not deployed yet)"
else
    echo "❌ Neither MVO nor OADP found"
fi

echo ""
echo "✅ Health Check Complete"

# Return appropriate exit code
if echo "$CSV_STATUS" | grep -q "Succeeded" && echo "$PODS" | grep -q "Running"; then
    echo "🎉 OADP is healthy on this cluster"
    exit 0
else
    echo "⚠️  OADP issues detected on this cluster"
    exit 1
fi