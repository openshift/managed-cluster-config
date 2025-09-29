# Velero Configuration & OADP Migration

This directory contains backup and restore configurations for Red Hat managed clusters, including the migration from Managed Velero Operator (MVO) to OpenShift API for Data Protection (OADP).

## Directory Structure

### Main Configuration (Legacy)
- `100-velero.Velero.yaml` - Legacy VeleroInstall resource (MVO)
- `110-velero.Schedules.yaml` - Backup schedules for general clusters
- `120-velero.Secret-Role.yaml` - RBAC for secret access
- `130-velero.Secret-RoleBinding.yaml` - Role bindings for secrets

### Hive-Specific Configuration
- `hive-specific/` - **Complete OADP migration for Hive clusters**

## OADP Migration Strategy

### Phase 1: OADP Installation (Hive Clusters Only)
The `hive-specific/` directory now contains the complete OADP operator installation and configuration for Hive-managed clusters:

**OADP Operator Installation:**
- `100-oadp.Subscription.yaml` - OADP operator subscription
- `110-oadp.Namespace.yaml` - openshift-adp namespace
- `120-oadp.OperatorGroup.yaml` - Operator group setup

**OADP Configuration:**
- `130-oadp.DataProtectionApplication.yaml` - Main DPA configuration with environment variables
- `140-oadp.TestBackup.yaml` - Validation backup for testing

**OADP RBAC & Schedules:**
- `05-oadp-schedule-admins-cluster.ClusterRole.yaml` - Enhanced RBAC for OADP resources
- `111-oadp.Schedules.yaml` - Backup schedules (migrated from Velero)

### Target Clusters (Hive-Specific)
- Clusters with `ext-managed.openshift.io/hive-shard: "true"` label
- Excludes FedRAMP clusters (`api.openshift.com/fedramp != "true"`)

### Environment Variables Required
- `${OADP_BACKUP_BUCKET}` - S3 bucket name for storing backups
- `${AWS_REGION}` - AWS region where the bucket is located

## Migration Timeline

1. ✅ **Phase 1**: Deploy OADP operator and configuration to Hive clusters
2. 🔄 **Phase 2**: Validate OADP functionality and backup operations
3. 🔄 **Phase 3**: Remove MVO from clusters with successful OADP deployment

## Related Issues

- SREP-1607: Setup OADP for RH Internal Clusters after MVO Removal

## References

- [OADP Documentation](https://docs.openshift.com/container-platform/latest/backup_and_restore/application_backup_and_restore/oadp-features-plugins.html)
- [Migration from MVO to OADP Guide](https://access.redhat.com/articles/oadp-migration)