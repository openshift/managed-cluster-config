# OADP Configuration for Red Hat Managed Clusters

This directory contains OpenShift API for Data Protection (OADP) operator configurations to replace the deprecated Managed Velero Operator (MVO) on Red Hat managed clusters.

## Overview

OADP provides backup and restore capabilities for OpenShift clusters and is the supported data protection solution for Red Hat managed clusters going forward.

## Components

### Main Configuration
- `100-oadp.Subscription.yaml` - OADP operator subscription
- `110-oadp.Namespace.yaml` - openshift-adp namespace creation
- `120-oadp.OperatorGroup.yaml` - Operator group for OADP
- `130-oadp.DataProtectionApplication.yaml` - Main DPA configuration
- `140-oadp.TestBackup.yaml` - Validation backup for testing

### Hive-Specific Configuration
- `hive-specific/config.yaml` - SelectorSyncSet configuration for Hive clusters
- `hive-specific/05-oadp-schedule-admins-cluster.ClusterRole.yaml` - RBAC for backup management
- `hive-specific/111-oadp.Schedules.yaml` - Backup schedule configuration

## Migration from MVO

This configuration replaces the Managed Velero Operator (MVO) with the following changes:

1. **Namespace**: Changed from `openshift-velero` to `openshift-adp`
2. **Operator**: Uses OADP operator instead of MVO
3. **API**: Uses DataProtectionApplication CRD instead of VeleroInstall
4. **RBAC**: Updated cluster roles to include OADP resources

## Environment Variables

The following environment variables must be configured for the DataProtectionApplication:

- `OADP_BACKUP_BUCKET` - S3 bucket name for storing backups
- `AWS_REGION` - AWS region where the bucket is located

## Deployment

This configuration is deployed via Hive SelectorSyncSets to clusters matching the selector criteria:
- Clusters with `ext-managed.openshift.io/hive-shard: "true"` label
- Excludes FedRAMP clusters

## Validation

After deployment, validate the installation:

1. Verify OADP operator is running:
   ```bash
   oc get pods -n openshift-adp
   ```

2. Check DataProtectionApplication status:
   ```bash
   oc get dpa -n openshift-adp
   ```

3. Verify backup schedule is created:
   ```bash
   oc get schedule -n openshift-adp
   ```

4. Test backup creation:
   ```bash
   oc create -f 140-oadp.TestBackup.yaml
   oc get backup -n openshift-adp
   ```

## Related Issues

- SREP-1607: Setup OADP for RH Internal Clusters after MVO Removal

## References

- [OADP Documentation](https://docs.openshift.com/container-platform/latest/backup_and_restore/application_backup_and_restore/oadp-features-plugins.html)
- [Original Velero Configuration](../velero-configuration/hive-specific/)