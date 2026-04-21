## Overview

Deploys the `rosa-cpus-instance-types-config` ConfigMap to the `hypershift` namespace on management clusters. This ConfigMap provides vCPU counts for EC2 instance types that cannot be resolved via the EC2 DescribeInstanceTypes API from management cluster AWS accounts.

The hypershift-operator (HO v0.1.75+, [OCPBUGS-50003](https://issues.redhat.com/browse/OCPBUGS-50003)) uses this ConfigMap as a fallback when the EC2 API returns `InvalidInstanceType`. Without it, the `hypershift_cluster_vcpus` metric reports `-1` for affected clusters, triggering `BillingMetricsMissing` alerts.

## Instance types

| Instance Type | vCPUs |
|---------------|-------|
| `i3.metal` | 72 |
| `g6.xlarge` | 4 |

## Adding new instance types

If a new `BillingMetricsMissing` alert fires for an unrecognized instance type, add an entry to `rosa-cpus-instance-types-config.yaml` mapping the instance type name to its vCPU count (as a string). Verify the vCPU count against the [AWS EC2 instance types documentation](https://docs.aws.amazon.com/ec2/latest/instancetypes/so.html).
