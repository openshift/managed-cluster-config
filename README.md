# managed-cluster-config repository

This repo contains static configuration specific to a "managed" OpenShift Dedicated (OSD) cluster.

## How to use this repo

To add a new SelectorSyncSet, add your yaml manifest to the `deploy` dir, then run the `make` command.

# Selector Sync Sets included in this repo

## Prometheus

A set of rules and alerts that SRE requires to ensure a cluster is functioning.  There are two categories of rules and alerts found here:

1. SRE specific, will never be part of OCP
2. Temporary addition until made part of OCP

### SLA/SLO Recording and Alerting Rules
Files under `deploy/sre-prometheus/` that start with `100-slo-` contain recording and alerting rules for our [managed cluster SLAs](https://mojo.redhat.com/docs/DOC-1189726). To edit them, edit `source/slo.csv` then run `./scripts/generate_slo_rules.py ./source/slo.csv -o ./deploy/sre-prometheus/` to generate the rule files. See `./scripts/generate_slo_rules.py -h` for more details.

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
