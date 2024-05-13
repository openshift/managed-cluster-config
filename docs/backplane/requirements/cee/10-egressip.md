# CEE on OSD/ROSA

label selectors:

- managed=true (implied)

These premissions are the baseline across the managed fleet and apply to all product flavors:

- OSD
- ROSA Classic
- ROSA HCP

## openshift-backplane-cee: `cluster`

These permissions are at cluster scope:

- get egressips
- list egressips
- watch egressips

* CEE needs read-only access to the `egressips` cluster resource. The `egreessips` is a non-sensetive data. Having read-only access will help CEE to investigate customer issues related to the `egressips`. 

