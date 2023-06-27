# Overview

For HyperShift, we need to patch certain namespaces to add labels that could help achieve functional goals. We don't do anything else directly with the namespace apart from adding labels. This is a single SSS to patch namespace labels for these use cases in HyperShift.

## Namespaces patched

- `openshift-observability-operator` ([OSD-13931](https://issues.redhat.com/browse/OSD-13931)) - The `network.openshift.io/policy-group: monitoring` network policy label is added to allow ingress traffic.
- `openshift-monitoring` ([OSD-15906](https://issues.redhat.com/browse/OSD-15906)) - Adds a common label `hypershift.openshift.io/monitoring` that identifies the namespace should be being monitored by Observability Operator.
