# OADP Operator Installation for Red Hat Managed Clusters

This directory contains OpenShift API for Data Protection (OADP) operator installation manifests specifically for Red Hat managed/internal clusters.

## Overview

This configuration installs the OADP operator on Red Hat managed clusters only. It is designed to work alongside the main OADP configuration in `/deploy/oadp-configuration/` which provides the DataProtectionApplication and backup schedules.

## Target Clusters

This installation targets **Red Hat managed clusters only**:
- Clusters with `api.openshift.com/customer = redhat`
- Excludes FedRAMP clusters
- Excludes customer production clusters

## Components

- `100-oadp.Subscription.yaml` - OADP operator subscription
- `110-oadp.Namespace.yaml` - openshift-adp namespace creation
- `120-oadp.OperatorGroup.yaml` - Operator group for OADP

## Deployment Strategy

1. **Phase 1**: This configuration installs OADP operator on Red Hat clusters
2. **Phase 2**: The `/deploy/oadp-configuration/` enables OADP with DataProtectionApplication
3. **Phase 3**: Remove MVO from clusters where OADP is successfully running

## Validation

After deployment, verify the operator installation:

```bash
# Check operator is installed
oc get csv -n openshift-adp | grep oadp

# Check operator pods are running
oc get pods -n openshift-adp

# Verify operator group and subscription
oc get operatorgroup,subscription -n openshift-adp
```

## Related Issues

- SREP-1607: Setup OADP for RH Internal Clusters after MVO Removal

## References

- [OADP Documentation](https://docs.openshift.com/container-platform/latest/backup_and_restore/application_backup_and_restore/oadp-features-plugins.html)
- [Main OADP Configuration](../oadp-configuration/)