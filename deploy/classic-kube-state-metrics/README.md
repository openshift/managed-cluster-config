# ROSA Classic Kube-State-Metrics

## What is Kube-State-Metrics (KSM)?

Kube-State-Metrics is a service that listens to the Kubernetes API and generates Prometheus metrics from the state of Kubernetes objects. It converts resource statuses into queryable metrics, enabling observability for resources that don't naturally expose metrics.

## Why Deploy to ROSA Classic Clusters?

In ROSA Classic environments, the machine-api-operator exposes basic metrics for MachineSets (replica counts), but does not expose spec-level details like spot instance configuration. This makes it impossible to distinguish between on-demand and spot instance provisioning failures in alerting.

By deploying this specialized KSM instance to ROSA Classic clusters, we generate metrics for the MachineSet spec fields we want to monitor. This enables:
- Detection of spot vs on-demand MachineSets
- Different alerting behavior for spot instance failures (expected) vs on-demand failures (requires investigation)
- Proper customer experience without false-positive service logs for spot capacity issues

## What This Deployment Does

This is an additional KSM deployment to the `openshift-machine-api-observability` namespace, separate from OpenShift's Cluster Monitoring Operator (CMO) KSM instance which does not support extensions for custom resource monitoring.

Currently configured to monitor MachineSet custom resources, this deployment converts their spec fields into Prometheus metrics. The configuration extracts:
- Instance type information
- Spot market configuration (presence of `spotMarketOptions` indicates spot instance)

## Example Metrics Generated

```prometheus
# HELP mapi_machine_set_spec_info Static spec-derived info for a machineset including spot market configuration
# TYPE mapi_machine_set_spec_info info
mapi_machine_set_spec_info{customresource_group="machine.openshift.io",customresource_kind="MachineSet",customresource_version="v1beta1",instance_type="m5.xlarge",name="my-cluster-worker-us-east-1a",namespace="openshift-machine-api",spot_market_max_price=""} 1
mapi_machine_set_spec_info{customresource_group="machine.openshift.io",customresource_kind="MachineSet",customresource_version="v1beta1",instance_type="m5.large",name="my-cluster-spot-worker-us-east-1b",namespace="openshift-machine-api",spot_market_max_price="0.10"} 1
```

**Note**: If `spot_market_max_price` label exists (even as empty string ""), the MachineSet is configured for spot instances. On-demand MachineSets will not have this label at all.

## Observability Integration

The deployment includes a ServiceMonitor using `monitoring.coreos.com/v1` API which integrates with the OpenShift Cluster Monitoring stack for automatic metrics collection.

## Deployment Target

This deployment targets **ROSA Classic clusters only** via SelectorSyncSet:
- Product: `rosa`
- Excludes HyperShift management/service clusters
- Excludes FedRAMP clusters

## Usage in Alerts

The exposed metrics are used in the MachineSet provisioning failure alert to:
1. Exclude spot instances from on-demand provisioning failure alerts (severity: critical)
2. Create separate spot instance provisioning alerts (severity: warning)
3. Send different service log messages to customers based on instance type

See `/deploy/sre-prometheus/100-machineset-not-reaching-desired-replicas.PrometheusRule.yaml` for alert implementation.

## Related Components

- **HyperShift equivalent**: `/deploy/hypershift-kube-state-metrics/` (monitors NodePools on management clusters)
- **Alert**: `/deploy/sre-prometheus/100-machineset-not-reaching-desired-replicas.PrometheusRule.yaml`
- **On-demand notification**: `/deploy/ocm-agent-operator-managednotifications/machineset-provisioning-failure/`
- **Spot notification**: `/deploy/ocm-agent-operator-managednotifications/machineset-provisioning-failure-spot/` (to be created)
