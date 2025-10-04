# OADP Deployment Validation Plan

## Quick Status Check Commands

### 1. Cluster Selection Validation
Check which clusters will receive OADP deployment:

```bash
# Check clusters with required labels
ocm list clusters --columns=id,name,state,product,labels | grep "hive-shard.*true"

# Exclude FedRAMP clusters (should not appear in results)
ocm list clusters --columns=id,name,state,product,labels | grep "fedramp.*true"
```

### 2. OADP Operator Status Check
For any target cluster:

```bash
# Login to cluster
ocm cluster login <cluster-name-or-id>

# Check OADP operator installation
oc get csv -n openshift-adp | grep oadp

# Expected result:
# oadp-operator.v1.4.5    OADP Operator    1.4.5    oadp-operator.v1.4.4    Succeeded
```

### 3. OADP Resources Validation
```bash
# Check all OADP resources exist
oc get subscription,operatorgroup,dpa,schedule,backup -n openshift-adp

# Check operator pods are running
oc get pods -n openshift-adp

# Expected: openshift-adp-controller-manager pod in Running state
```

### 4. Environment Variable Validation
```bash
# Check if DPA has correct bucket configuration
oc get dpa -n openshift-adp -o yaml | grep -A 5 "objectStorage:"

# Should show resolved bucket name (not ${OADP_BACKUP_BUCKET})
```

## PromQL Monitoring Queries

### OADP Operator Metrics
```promql
# OADP operator pod status
up{job="openshift-adp-controller-manager-metrics-service"}

# OADP operator successful installations
sum(kube_pod_status_ready{namespace="openshift-adp", condition="true"})

# CSV status for OADP operator
csv_succeeded{name=~"oadp-operator.*", namespace="openshift-adp"}
```

### Backup Activity Metrics
```promql
# Successful backups in last 24h
increase(velero_backup_success_total[24h])

# Failed backups in last 24h
increase(velero_backup_failure_total[24h])

# Backup duration
histogram_quantile(0.95, rate(velero_backup_duration_seconds_bucket[1h]))
```

### Hive SelectorSyncSet Metrics
```promql
# SelectorSyncSet application status
selectorsyncset_applied_total{name="velero-configuration-hive-specific"}

# Resource application failures
selectorsyncset_resource_apply_failure_total{name="velero-configuration-hive-specific"}
```

## Validation Checklist

### ✅ Pre-Deployment Validation
- [ ] Hive cluster targeting working (`ext-managed.openshift.io/hive-shard: true`)
- [ ] FedRAMP clusters excluded (`api.openshift.com/fedramp != true`)
- [ ] Environment variables configured (`OADP_BACKUP_BUCKET`, `AWS_REGION`)
- [ ] Channel set to `stable-1.4` in subscription

### ✅ Post-Deployment Validation
- [ ] OADP operator CSV in "Succeeded" state
- [ ] `openshift-adp-controller-manager` pod running
- [ ] DPA resource created with resolved bucket name
- [ ] Backup schedules active (e.g., `5min-object-backup`)
- [ ] No conflicting Velero resources in `openshift-velero` namespace

### ✅ Functional Validation
- [ ] Test backup completes successfully
- [ ] Prometheus metrics showing backup activity
- [ ] No error alerts in monitoring

## Quick Health Check Script

```bash
#!/bin/bash
# oadp-health-check.sh

CLUSTER_ID=${1:-"current"}

echo "🔍 OADP Health Check for cluster: $CLUSTER_ID"
echo "=============================================="

# If cluster ID provided, login first
if [ "$CLUSTER_ID" != "current" ]; then
    echo "🔐 Logging into cluster $CLUSTER_ID..."
    ocm cluster login $CLUSTER_ID
fi

echo ""
echo "📦 OADP Operator Status:"
oc get csv -n openshift-adp | grep oadp || echo "❌ OADP operator not found"

echo ""
echo "🏃 OADP Pods:"
oc get pods -n openshift-adp

echo ""
echo "📋 OADP Resources:"
oc get subscription,dpa,schedule -n openshift-adp

echo ""
echo "💾 Recent Backups:"
oc get backup -n openshift-adp --sort-by=.metadata.creationTimestamp | tail -5

echo ""
echo "✅ Health Check Complete"
```

## Monitoring Dashboard Queries

### OADP Deployment Status Panel
```promql
# Total clusters with OADP deployed
count(up{job="openshift-adp-controller-manager-metrics-service"})

# OADP operator health across all clusters
avg(up{job="openshift-adp-controller-manager-metrics-service"}) * 100
```

### Backup Success Rate Panel
```promql
# Backup success rate (last 24h)
(
  sum(increase(velero_backup_success_total[24h])) /
  (sum(increase(velero_backup_success_total[24h])) + sum(increase(velero_backup_failure_total[24h])))
) * 100
```

## Troubleshooting Quick Commands

### OADP Operator Issues
```bash
# Check operator logs
oc logs -n openshift-adp deployment/openshift-adp-controller-manager

# Check subscription status
oc describe subscription openshift-adp -n openshift-adp

# Check install plan
oc get installplan -n openshift-adp
```

### Backup Issues
```bash
# Check backup details
oc describe backup <backup-name> -n openshift-adp

# Check Velero logs
oc logs -n openshift-adp deployment/velero

# Check backup location status
oc get backupstoragelocation -n openshift-adp
```

## Migration Status Tracking

### Phase 1: OADP Deployment (Current)
```bash
# Count target clusters
ocm list clusters --parameter="search=labels.key='ext-managed.openshift.io/hive-shard' and labels.value='true'" | wc -l

# Count clusters with OADP deployed
# (Run on each target cluster)
oc get csv -n openshift-adp | grep oadp | wc -l
```

### Phase 2: Velero Coexistence Check
```bash
# Check both systems running
oc get pods -n openshift-velero  # MVO pods
oc get pods -n openshift-adp     # OADP pods

# Verify no resource conflicts
oc get clusterrole | grep -E "(velero|oadp)"
```

### Phase 3: MVO Cleanup (Future)
```bash
# Verify MVO resources removed
oc get all -n openshift-velero
oc get clusterrole | grep velero
```

## Emergency Rollback Commands

If OADP causes issues:

```bash
# Quick OADP removal (emergency only)
oc delete subscription openshift-adp -n openshift-adp
oc delete csv -n openshift-adp --all
oc delete namespace openshift-adp

# Verify MVO still functional
oc get pods -n openshift-velero
oc get backup -n openshift-velero
```

## Success Criteria

✅ **OADP Successfully Deployed When:**
- All target Hive clusters have OADP operator in "Succeeded" state
- Backup schedules are active and completing successfully
- No conflicts with existing MVO installation
- Environment variables properly resolved in DPA configuration
- Prometheus metrics showing healthy backup activity

🎯 **Key Metrics to Monitor:**
- OADP operator uptime: >99%
- Backup success rate: >95%
- Deployment coverage: 100% of target Hive clusters
- Zero resource conflicts between OADP and MVO