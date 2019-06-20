# managed-cluster-config repository

This repo contains static configuration specific to a "managed" OpenShift Dedicated (OSD) cluster.

## How to use this repo

To add a new SelectorSyncSet, add your yaml manifest to the `deploy` dir, then run the `make` command.

# Selector Sync Sets included in this repo

## Prometheus

A set of rules and alerts that SRE requires to ensure a cluster is functioning.  There are two categories of rules and alerts found here:

1. SRE specific, will never be part of OCP
2. Temporary addition until made part of OCP

## Prometheus and Alertmanager persistent storage

Persistent storage is configured using the configmap `cluster-monitoring-config`, which is read by the cluster-monitoring-operator to generate PersistentVolumeClaims and attach them to the Prometheus and Alertmanager pods.

## SRE Authorization

Instead of SRE having `cluster-admin` a new ClusterRole is created with some permissions removed.  The ClusterRole can be regenerated in the `generate/sre-authorization` directory.

## Console Branding

Docs TBA.

## OAuth Templates

Docs TBA.

## Resource Quotas

Refer to [deploy/resource/quotas/README.md](deploy/resource/quotas/README.md).

## Image Pruning

Docs TBA.

## Dependencies

pyyaml

## Logging

Installs ES and logging operators and pre-configures curator to retain 2 days of indexes (1 day for operations).

Customer can install a `ClusterLogging` CR in `openshift-logging` as a `dedicated-admins` user to opt-in to logging in the cluster.

# Additional Scripts

There are additional scripts in this repo as a holding place for a better place or a better solution / process.

## Cluster Upgrade

Script `scripts/create-upgrade.sh` is used to upgrade all clusters managed by one Hive instance.  The script requires two inputs: the starting version and the target version.  If the target version is not available in the upgrade graph the upgrade will not be done.

To use the script:
1. kubectl/oc login into the desired Hive cluster
2. run the script, i.e. scripts/cluster-upgrade.sh 4.1.0 4.1.1
3. do #2 until there are no clusters listed as "progressing"

Note the script isn't a perfect solution.  It requires being run multiple times.  Whoever runs it must watch how long cluster upgrades are progressing.  If a cluster is taking a long time it's possible additional steps are needed in the cluster.  Usually this is some cluster operator is in a degraded state and needs fixing.
