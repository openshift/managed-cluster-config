# OADP Test Plan for oadp-test-cluster

## Cluster Information
- **Cluster ID**: 2ljqvfpi5lifjf83uedn9dcg9okoiktv
- **Name**: oadp-test-cluster
- **Version**: OpenShift 4.18.24
- **Provider**: AWS (us-east-1)

## Test Sequence

### 1. Cluster Readiness Check
```bash
# Check cluster status
ocm describe cluster oadp-test-cluster

# Wait for cluster to be 'ready'
# API URL and Console URL should be populated
```

### 2. Connect to Cluster
```bash
# Login to cluster
ocm cluster login oadp-test-cluster

# Verify connection
oc whoami
oc cluster-info
```

### 3. Check Hive Selector Criteria
Our OADP config requires:
- `ext-managed.openshift.io/hive-shard: "true"`
- `api.openshift.com/fedramp != "true"`

### 4. Test OADP Configuration Deployment
```bash
# Set environment variables (simulate Hive environment)
export OADP_BACKUP_BUCKET="test-oadp-backup-bucket"
export AWS_REGION="us-east-1"

# Apply OADP configurations
oc apply -f deploy/velero-configuration/hive-specific/110-oadp.Namespace.yaml
oc apply -f deploy/velero-configuration/hive-specific/120-oadp.OperatorGroup.yaml
oc apply -f deploy/velero-configuration/hive-specific/100-oadp.Subscription.yaml

# Apply DPA with environment substitution
envsubst < deploy/velero-configuration/hive-specific/130-oadp.DataProtectionApplication.yaml | oc apply -f -
```

### 5. Verification Commands
```bash
# Check OADP operator status
oc get subscription -n openshift-adp
oc get csv -n openshift-adp
oc get pods -n openshift-adp

# Check DPA status
oc get dpa -n openshift-adp
oc describe dpa dpa-sample -n openshift-adp
```