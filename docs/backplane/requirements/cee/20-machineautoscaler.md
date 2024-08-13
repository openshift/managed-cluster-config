# CEE on OSD/ROSA

label selectors:

- managed=true (implied)

These premissions are the baseline across the managed fleet and apply to all product flavors:

- OSD
- ROSA Classic

## openshift-backplane-cee: `cluster`

These permissions are at cluster scope:

- get machineautoscaler
- list machineautoscaler
- watch machineautoscaler

* CEE needs read-only access to the `machineautoscaler` cluster resource. The `machineautoscaler` is a non-sensetive data. Having read-only access will help CEE to investigate customer issues related to the `machineautoscaler` and the `clusterautoscaler`. 

