# Rebalancing Infra Nodes on cluster

This is used to evenly distribute SRE workloads on infra nodes, so that infra nodes aren't starved of resources and necessary SRE workloads aren't degraded.

## non-FedRAMP

- Managed Node Metadata Operator
- OCM Agent Operator
- OSD Metrics Exporter

## non-STS and non-WIF

Velero Operator is only installed on clusters which are neither STS nor WIF, so the relevant RBAC will only be applied to those clusters

## non-STS and non-WIF and non-PrivateLink

Cloud Ingress Operator is only installed on clusters which are neither STS, WIF nor PrivateLink, so the relevant RBAC will only be applied to those clusters.
