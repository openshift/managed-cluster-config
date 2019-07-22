# managed-cluster-config repository

This repo contains static configuration specific to a "managed" OpenShift Dedicated (OSD) cluster.

## How to use this repo

Yaml files are taken from [./deploy/](./deploy/) dir and deployed through couple layers of indirection:

1.  Each yaml from ./deploy/ gets wrapped it in a [Hive `SelectorSyncSet`] according to [scripts/templates/selectorsyncset.yaml](scripts/templates/selectorsyncset.yaml).

    If the yaml contains `patch` field, it is put under `patches:` in the `SelectorSyncSet`, otherwise it's copied under `resources:`.

    Hive looks for `SelectorSyncSet` resources *in the Hive cluster* matching `ClusterDeployment` labels and creates/syncs the resources / applies the patches described inside into the corresponding clusters.

2.  To allow variations between prod/stage/integration environments, the resulting `SelectorSyncSet`s are wrapped in an openshift `Template` according to [./scripts/templates/template.yaml](./scripts/templates/template.yaml). (This file also contains some fixed resources where wrapping step 1 doesn't fit.)

    The per-environment values for these parameters come from [saas-osd-operators repo](https://gitlab.cee.redhat.com/service/saas-osd-operators/blob/master/managed-cluster-config-services/managed-cluser-config.yaml).

Thus to add a new resource, add your yaml manifest to the ./deploy/ dir.
Write the yaml as you want it to exist *inside* the OSD cluster, say if you want a ConfigMap, use `kind: ConfigMap`.  Except you can use `${...}` parameters from the template.

To patch existing resource in the cluster, again add a yaml manifest to the ./deploy/ dir, but include `patch`, `patchType`, `applyMode` fields at top level — see [Hive `SelectorSyncSet`] docs.

Then run the `make` command, and commit the generated changes too.

[Hive `SelectorSyncSet`]: https://github.com/openshift/hive/blob/master/docs/syncset.md

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
