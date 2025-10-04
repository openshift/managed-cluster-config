# OSD Master Node Labeller

This SelectorSyncSet deploys a CronJob that automatically adds the `node-role.kubernetes.io/control-plane` label to all nodes that have the `node-role.kubernetes.io/master` label.

## Overview

In Kubernetes/OpenShift, the `node-role.kubernetes.io/master` label has been deprecated in favor of `node-role.kubernetes.io/control-plane`. This cronjob ensures backward compatibility by automatically adding the new control-plane label to nodes that still only have the legacy master label.

## Components

- **ServiceAccount**: `osd-master-node-labeller` - Service account for the cronjob
- **ClusterRole**: Grants permissions to list, get, and patch nodes
- **ClusterRoleBinding**: Binds the ClusterRole to the ServiceAccount
- **CronJob**: Runs every 5 minutes to label master nodes

## Logic

The CronJob runs a bash script that:

1. Queries all nodes with the `node-role.kubernetes.io/master` label
2. For each master node, checks if it already has the `node-role.kubernetes.io/control-plane` label
3. If the control-plane label is missing, adds it to the node
4. Logs all operations for visibility

## Target Clusters

This configuration is deployed to:
- **Products**: OSD and ROSA clusters
- **Versions**: OpenShift 4.14 through 4.18 only
- **Resource Apply Mode**: Sync

## Schedule

The CronJob runs every 5 minutes (`*/5 * * * *`) to ensure newly provisioned or updated nodes are labeled promptly.

## Node Affinity

The job preferentially runs on infra nodes to minimize impact on customer workloads.
