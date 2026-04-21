# non-hcp

This directory contains Prometheus alerts and monitoring rules that are deployed **only to classic OSD/ROSA clusters**; NOT to Hypershift Management or Service clusters.

## Purpose

Resources in this directory are excluded from HyperShift infrastructure clusters to avoid configuration mismatches for components that don't exist on those cluster types (ie - `console` RouteMonitors from RMO)

## Target Clusters

### ✅ Deployed To:
- **Classic OSD clusters** (standalone, non-HyperShift)
- **Classic ROSA clusters** (standalone, non-HyperShift)

### ❌ NOT Deployed To:
- **Management Clusters** (`ext-hypershift.openshift.io/cluster-type: management-cluster`)
- **Service Clusters** (`ext-hypershift.openshift.io/cluster-type: service-cluster`)
- **FedRAMP Clusters** (`api.openshift.com/fedramp: true`)

## Selector Configuration

The `config.yaml` in this directory uses the following selector:

```yaml
selectorSyncSet:
  matchExpressions:
  - key: ext-hypershift.openshift.io/cluster-type
    operator: NotIn
    values:
      - "management-cluster"
      - "service-cluster"
  - key: api.openshift.com/fedramp
    operator: NotIn
    values:
      - "true"
```

This ensures that resources are only deployed to clusters that do **not** have a HyperShift cluster-type label.

## Current Resources

- **Console probe monitoring**: Alerts for missing `probe_success` metrics for the web console endpoint, which only exist on classic clusters.

## When to Add Resources Here

Add monitoring resources to this directory when:

1. The monitored component or endpoint **does not exist** on HyperShift management/service clusters
2. The alert would fire incorrectly on HyperShift infrastructure due to architectural differences
3. The resource is specific to the classic OSD/ROSA cluster architecture

## See Also

- Parent directory (`../`) contains alerts deployed to **all** managed clusters
- `../management-cluster/` contains alerts specific to HyperShift management clusters
