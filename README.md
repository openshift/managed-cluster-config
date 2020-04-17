# managed-cluster-config repository

This repo contains static configuration specific to a "managed" OpenShift Dedicated (OSD) cluster.

## How to use this repo

To add a new SelectorSyncSet, add your yaml manifest to the `deploy` dir, then run the `make` command.

# Building

## Dependencies

- oyaml: `pip install oyaml`

# Selector Sync Set Configuration
There is a limited configuration available at this time.  The file `sss-config.yaml` contains configurations that apply to the current directory only and it supports the following features:

* matchLabels (default: `{}`) - adds additional `matchLabels` conditions to the `clusterDeploymentSelector`
* resourceApplyMode (default: `"Sync"`) - sets the `resourceApplyMode`
* matchLabelsApplyMode (optional, default: not set) - When set as `"OR"` generates a separate SSS per `matchLabels` conditions. Default behavior creates a single SSS with all `matchLabels` conditions.  This is to tackle a situation where we want to apply configuration for one of many label conditions.

# Selector Sync Sets included in this repo

## Prometheus

A set of rules and alerts that SRE requires to ensure a cluster is functioning.  There are two categories of rules and alerts found here:

1. SRE specific, will never be part of OCP
2. Temporary addition until made part of OCP

## Prometheus and Alertmanager persistent storage

Persistent storage is configured using the configmap `cluster-monitoring-config`, which is read by the cluster-monitoring-operator to generate PersistentVolumeClaims and attach them to the Prometheus and Alertmanager pods.

## SRE Authorization

Instead of SRE having the `cluster-admin` role, a new ClusterRole, `osd-sre-admin`, is created with some permissions removed.  The ClusterRole can be regenerated in the `generate/sre-authorization` directory.  The role is granted to SRE via `osd-sre-admins` group.

To elevate privileges, SRE can add themselves to the group `osd-sre-cluster-admins`, which is bound to the ClusterRole `cluster-admin`.  When this group is created and managed by Hive, all users are wiped because the SelectorSyncSet will always have `users: null`.  Therefore, SRE will get elevated privileges for a limited time.

## Curated Operators

Initially OSD will support a subset of operators only.  These are managed by patching the OCP shipped OperatorSource CRs.  See `deploy/osd-curated-operators`.

NOTE that ClusterVersion is being patched to add overrides.  If other overrides are needed we'll have to tune how we do this patching.  It must be done along with the OperatorSource patching to ensure CVO doesn't revert the OperatorSource patching.

## Console Branding

Docs TBA.

## OAuth Templates

Docs TBA.

## Resource Quotas

Refer to [deploy/resource/quotas/README.md](deploy/resource/quotas/README.md).

## Image Pruning

Docs TBA.

## Logging

Prepares the cluster for `elasticsearch` and `logging` operator installation and pre-configures curator to retain 2 days of indexes (1 day for operations).

To opt-in to logging, the customer must:
1. install the `logging` operator
2. install the `elasticsearch` operator
3. create `ClusterLogging` CR in `openshift-logging`

## EFS Enablement via CSI

[`efs-csi`](deploy/efs-csi) enables AWS EFS via the CSI driver. Customer
opts in by opening a ServiceNow ticket, whereupon SRE must add the appropriate
[label](deploy/efs-csi/sss-config.yaml) to the cluster. The
SelectorSyncSet:

- Installs a DaemonSet into the `kube-system` namespace, running the CSI driver
  image on worker nodes.
- Creates a CSIDriver resource.
- Creates a StorageClass pointing to the CSIDriver.
- Sets up a ClusterRoleBinding allowing dedicated-admins to create
  PersistentVolumes.
- Creates a SecurityContextConstraints allowing dedicated-admins to
  create pods with any UID.

# Dependencies

pyyaml


# Additional Scripts

There are additional scripts in this repo as a holding place for a better place or a better solution / process.

## Cluster Upgrade

Script `scripts/create-upgrade.sh` is used to upgrade all clusters managed by one Hive instance.  The script requires two inputs: the starting version and the target version.  If the target version is not available in the upgrade graph the upgrade will not be done.

To use the script:
1. kubectl/oc login into the desired Hive cluster
2. run the script, i.e. scripts/cluster-upgrade.sh 4.1.0 4.1.1
3. do #2 until there are no clusters listed as "progressing"

Note the script isn't a perfect solution.  It requires being run multiple times.  Whoever runs it must watch how long cluster upgrades are progressing.  If a cluster is taking a long time it's possible additional steps are needed in the cluster.  Usually this is some cluster operator is in a degraded state and needs fixing.
