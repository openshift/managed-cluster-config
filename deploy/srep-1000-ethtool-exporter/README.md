# SREP-1000-ethtool-exporter

Per SREP-1000, this contains a SelectorSyncSet config that targets `Management-Clusters` to deploy a supplemental node-exporter using the ethtool.collector. This is then used by openshift-monitoring prometheus-k8s to scrape AWS packet drop metrics related to ENA exceeding their allowed bandwidth as defined by the instance type.
CMO does not currently support the ethtool collector. This SSS can be removed once support is added to CMO (See RFE-7342).

## Metrics

The serviceMonitor is currently filtering all but the following metrics:

- bw_in_allowance_exceeded
- bw_out_allowance_exceeded
- conntrack_allowance_exceeded
- linklocal_allowance_exceeded
- pps_allowance_exceeded

For more information on these metrics see AWS documentation:
https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-network-performance-ena.html#network-performance-metrics