# Hypershift Control Plane Log Forwarding

This directory contains configuration for forwarding logs from Red Hat OpenShift Service on AWS (ROSA) Hypershift Hosted Control Plane (HCP) management clusters to AWS S3 storage.

> **Note**: The OpenTelemetry Collector configuration files in this directory (35-otel-collector-config.yaml, 55-otel-daemonset.yaml) and this README were created with assistance from Claude (Anthropic AI Assistant).

## Overview

This directory contains configuration for two different log forwarding implementations:

- **Vector** - Production log collector
- **OpenTelemetry Collector** - Alternative implementation for evaluation/comparison

**Note**: Only one collector will be enabled at a time. Both configurations are maintained in this directory to facilitate comparison and potential migration between implementations.

When enabled, the selected collector runs as a DaemonSet on HCP nodes, collects logs from pods with the `hypershift.openshift.io/hosted-control-plane=true` namespace label, and writes to S3 with collector-specific file naming patterns.

## Vector Configuration

### Components

- **30-vector-config.yaml** - ConfigMap containing Vector configuration
- **50-daemonset.yaml** - Vector DaemonSet deployment
- **60-podmonitor.yaml** - Prometheus PodMonitor for both Vector and OTEL collectors

### Vector S3 Output Format

**Path**: `s3://{bucket}/{mc_cluster_id}/{namespace}/{application}/{pod_name}/{container_name}/`

**Filename**: `{uuid}-{YYYYMMDD-HHMMSS}.json.gz`

Example: `550e8400-e29b-41d4-a716-446655440000-20241013-123045.json.gz`

### Vector Image

Uses the OpenShift Logging Vector image: `quay.io/openshift-logging/vector:v0.47.0`

## OpenTelemetry Collector Configuration

### Components

- **35-otel-collector-config.yaml** - ConfigMap containing OTEL Collector configuration
- **55-otel-daemonset.yaml** - OTEL Collector DaemonSet deployment

### OTEL S3 Output Format

**Path**: `s3://{bucket}/{mc_cluster_id}/{namespace}/{application}/{pod_name}/{container_name}/`

**Filename**: `otel-{YYYYMMDD-HHMMSS}/{unique_id}.json.gz`

Example: `otel-20241013-123045/abc123.json.gz`

**Note**: The OTEL AWS S3 exporter creates timestamp-based subdirectories rather than embedding timestamps directly in filenames like Vector does.

### OTEL Image

Uses the OpenTelemetry Collector Contrib distribution: `otel/opentelemetry-collector-contrib:0.115.1`

### Persistent Storage

OTEL Collector uses persistent on-disk Write-Ahead Log (WAL) for reliability:
- **HostPath**: `/var/lib/otelcol-data`
- **Container Mount**: `/var/lib/otelcol`
- **Purpose**: File storage queue for S3 exporter to survive pod restarts

### Output Format Differences

The OTEL Collector outputs logs in **OTLP JSON format** (OpenTelemetry Protocol), which differs from Vector's output:

- **Structure**: OTLP semantic conventions vs Vector's event model
- **Timestamp Parsing**: Basic CRI-O timestamp only (no advanced parsing like Vector)
- **Metadata Location**: Resource attributes (`resource.attributes.*`) vs top-level fields
- **Log Body**: OTLP `body` field vs Vector's `message` field

### Alternative: Using OpenTelemetry Operator

The current implementation deploys the OTEL Collector as a manual DaemonSet. However, this repository uses the OpenTelemetry Operator for other OTEL deployments (see `deploy/backplane/*/dynatrace/otel` for RBAC examples).

#### Converting to Operator-Managed Deployment

To use the OpenTelemetry Operator instead of a manual DaemonSet:

1. **Remove manual resources**:
   - Delete `55-otel-daemonset.yaml`
   - Keep `35-otel-collector-config.yaml` for reference

2. **Create OpenTelemetryCollector CR**:

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-log-collector
  namespace: hypershift-control-plane-log-forwarding
spec:
  mode: daemonset
  image: otel/opentelemetry-collector-contrib:0.115.1

  serviceAccount: control-plane-log-forwarding

  env:
    - name: AWS_REGION
      value: "{{ fromCDLabel \"ext-hypershift.openshift.io/cluster-region\" }}"
    - name: MC_CLUSTER_ID
      value: "{{ fromCDLabel \"api.openshift.com/id\" }}"
    - name: S3_BUCKET_NAME
      valueFrom:
        configMapKeyRef:
          name: log-forwarding-config
          key: s3_bucket_name
    - name: S3_WRITER_ROLE_ARN
      valueFrom:
        configMapKeyRef:
          name: log-forwarding-config
          key: s3_writer_role_arn

  resources:
    limits:
      cpu: 200m
      memory: 2Gi
    requests:
      cpu: 50m
      memory: 256Mi

  securityContext:
    runAsUser: 0
    privileged: true

  volumeMounts:
    - name: varlog
      mountPath: /var/log
      readOnly: true
    - name: varlibdockercontainers
      mountPath: /var/lib/docker/containers
      readOnly: true
    - name: otel-data
      mountPath: /var/lib/otelcol

  volumes:
    - name: varlog
      hostPath:
        path: /var/log
    - name: varlibdockercontainers
      hostPath:
        path: /var/lib/docker/containers
    - name: otel-data
      hostPath:
        path: /var/lib/otelcol-data
        type: DirectoryOrCreate

  tolerations:
    - key: "hypershift.openshift.io/control-plane"
      effect: NoSchedule
      operator: Exists
    - key: "hypershift.openshift.io/request-serving-component"
      effect: NoSchedule
      operator: Exists
    - key: "hypershift.openshift.io/cluster"
      effect: NoSchedule
      operator: Exists

  config: |
    # Paste the entire config from 35-otel-collector-config.yaml here
    receivers:
      filelog:
        include:
          - /var/log/pods/*/*/*.log
        # ... (rest of config)
```

#### Operator Deployment Considerations

**Prerequisites**:
- OpenTelemetry Operator must be installed in the cluster
- Operator must be running in `openshift-opentelemetry-operator` namespace

**Advantages**:
- Consistent with repository patterns for OTEL management
- Operator handles lifecycle management, upgrades, and configuration updates
- Built-in monitoring and status reporting via CR status

**Disadvantages**:
- Adds dependency on operator availability
- Operator may impose restrictions or defaults that conflict with requirements
- Less direct control over pod specification compared to manual DaemonSet

**Template Considerations**:
- The `{{ fromCDLabel }}` Hive template syntax in the CR may not work directly
- May need to use envFrom with ConfigMaps/Secrets instead
- Consider using resource attribute substitution within OTEL config rather than env vars

**Current Decision**: Manual DaemonSet deployment provides more direct control and avoids operator dependency for this critical log forwarding component.

## Shared Resources

The following resources are shared between both Vector and OTEL collectors:

- **00-namespace.yaml** - Namespace definition
- **10-serviceaccount.yaml** - ServiceAccount (managed by OSDFM)
- **10-clusterrole.yaml** - ClusterRole for reading pods/namespaces/nodes
- **10-security-context-constraint.yaml** - SCC for privileged access to host paths
- **15-clusterrolebinding.yaml** - ClusterRoleBinding
- **60-podmonitor.yaml** - PodMonitor for Prometheus metrics scraping

Both collectors use the same RBAC and security permissions since they require identical access to cluster resources and host paths.

## S3 Configuration

Both collectors require the following configuration (provided by Fleet Manager):

**ConfigMap**: `log-forwarding-config`
- `s3_bucket_name` - Target S3 bucket
- `s3_writer_role_arn` - IAM role ARN for S3 write access (IRSA)

**Environment Variables** (injected via Hive templates):
- `MC_CLUSTER_ID` - Management cluster ID (from `api.openshift.com/id` label)
- `AWS_REGION` - AWS region (from `ext-hypershift.openshift.io/cluster-region` label)

## Deployment Targeting

This configuration is deployed only to ROSA Hypershift management clusters:

```yaml
selectorSyncSet:
  matchExpressions:
  - key: ext-hypershift.openshift.io/cluster-type
    operator: In
    values: ["management-cluster"]
  - key: api.openshift.com/fedramp
    operator: NotIn
    values: ["true"]
```

## Monitoring

Both collectors expose Prometheus metrics:

- **Vector**: Port 9598 at `/metrics`
- **OTEL**: Port 8888 at `/metrics`

The shared PodMonitor (60-podmonitor.yaml) scrapes both collectors using label matching on `app: control-plane-log-forwarding` and `app: otel-log-collector`.

## Troubleshooting

### Checking Collector Status

```bash
# Vector pods
oc get pods -n hypershift-control-plane-log-forwarding -l app=control-plane-log-forwarding

# OTEL pods
oc get pods -n hypershift-control-plane-log-forwarding -l app=otel-log-collector

# Check logs
oc logs -n hypershift-control-plane-log-forwarding -l app=control-plane-log-forwarding
oc logs -n hypershift-control-plane-log-forwarding -l app=otel-log-collector
```

### Verifying S3 Output

```bash
# List recent uploads (adjust path as needed)
aws s3 ls s3://${BUCKET}/${CLUSTER_ID}/ --recursive | tail -20

# Check Vector files
aws s3 ls s3://${BUCKET}/${CLUSTER_ID}/ --recursive | grep -v "^otel-"

# Check OTEL files
aws s3 ls s3://${BUCKET}/${CLUSTER_ID}/ --recursive | grep "otel-"
```
