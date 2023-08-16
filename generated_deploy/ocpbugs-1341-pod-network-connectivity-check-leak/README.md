# OCPBUGS-1341

## About

This sets up a `CronJob` on the cluster which aims to detect and remediate any PodNetworkConnectivityCheck leakage from [OCPBUGS-1341][].

A cluster which is impacted by this issue:
- Will have unused PodNetworkConnectivityCheck resources left behind due to node churn.

The fix of the CronJob is to:
- Remove the leaked PodNetworkConnectivityChecks.

## References:
* [OCPBUGS-1341][]

[OCPBUGS-1341]: https://issues.redhat.com/browse/OCPBUGS-1341
