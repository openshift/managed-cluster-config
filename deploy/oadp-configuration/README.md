# OADP Configuration for Red Hat Managed Clusters (Enable-Only)

This directory contains OpenShift API for Data Protection (OADP) configurations to enable backup and restore functionality on clusters where the OADP operator is already installed.

## Overview

OADP provides backup and restore capabilities for OpenShift clusters and is the supported data protection solution for Red Hat managed clusters going forward. This configuration assumes the OADP operator is pre-installed and only enables/configures the backup functionality.

## Prerequisites

- OADP operator must be pre-installed in `openshift-adp` namespace
- Cloud credentials must be properly configured for backup storage access
- Environment variables `${OADP_BACKUP_BUCKET}` and `${AWS_REGION}` must be set

## Components

### Main Configuration
- `130-oadp.DataProtectionApplication.yaml` - Main DPA configuration (enables OADP)
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

After deployment, validate the OADP configuration:

1. Verify OADP operator is already running (prerequisite):
   ```bash
   oc get pods -n openshift-adp
   ```

2. Check DataProtectionApplication was created and is ready:
   ```bash
   oc get dpa -n openshift-adp
   oc describe dpa dpa-sample -n openshift-adp
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