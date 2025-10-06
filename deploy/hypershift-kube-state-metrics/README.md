# Hypershift Kube-State-Metrics

## What is Kube-State-Metrics (KSM)?

Kube-State-Metrics is a service that listens to the Kubernetes API and generates Prometheus metrics from the state of Kubernetes objects. It converts resource statuses into queryable metrics, enabling observability for resources that don't naturally expose metrics.

## Why Deploy to Management Clusters?

In ROSA HCP environments, we're lacking comprehensive metrics for critical infrastructure components. Management clusters host Cluster API resources like machines, but their statuses aren't exposed as metrics by default.

By deploying this specialized KSM instance to management clusters, we generate metrics ourselves for the statuses we want to monitor. This enables quick plug-in observability for ROSA HCP without requiring changes to core platform components.

## What This Deployment Does

This is an additional KSM deployment to the `hypershift-observability` namespace, separate from OpenShift's Cluster Monitoring Operator (CMO) KSM instance which does not support extensions for custom resource monitoring.

Currently configured to monitor Cluster API Machine resources, this deployment converts their status fields into Prometheus metrics. The configuration is extensible to monitor any Kubernetes resources as needed.

## Example Metrics Generated

```prometheus
# HELP capi_machine_info The current state of a machine.
# TYPE capi_machine_info info
capi_machine_info{_id="2lctq83qt6ijsojsi41n5836fkd7m87c",customresource_group="cluster.x-k8s.io",customresource_kind="Machine",customresource_version="v1beta1",healthcheck_succeeded="True",infrastructure_ready="True",machine_name="kirk-brand-hcp-workers-0-v54m7-pzxdf",exported_namespace="ocm-int-2lctq83qt6ijsojsi41n5836fkd7m87c-kirk-brand-hcp",node_healthy="True",ready="True",status_phase="Running"} 1
capi_machine_info{_id="2lctq83qt6ijsojsi41n5836fkd7m87c",customresource_group="cluster.x-k8s.io",customresource_kind="Machine",customresource_version="v1beta1",healthcheck_succeeded="True",infrastructure_ready="True",machine_name="kirk-brand-hcp-workers-1-ks6v6-mc6vd",exported_namespace="ocm-int-2lctq83qt6ijsojsi41n5836fkd7m87c-kirk-brand-hcp",node_healthy="True",ready="True",status_phase="Running"} 1
```

## Observability Integration

The deployment includes a ServiceMonitor using `monitoring.rhobs/v1` API which integrates with the Red Hat Observability Stack for automatic metrics collection.