# *ACS Team* for *OSD/ROSA*

Process is captured [ROX-22017: Harden Network Security API Permissions](https://docs.google.com/document/d/1lyzFjK51py6o62zS5ErPFLbCNVJfq4e5PvVI2Y2z0Mg/edit)

label selectors:
* label `api.openshift.com/addon-acs-fleetshard: "true"`
        `api.openshift.com/addon-acs-fleetshard-qa: "true"`
        `api.openshift.com/addon-acs-fleetshard-dev: "true"` for where access is applied

These permissions are a baseline acess for the ACS:CS team across OSD/ROSA infra.

## backlplane-acs-admins-cluster: `cluster`
Permissions at cluster scope. `TBD`

* view machine resources
* view ingresscontrollers
* view ingresses
* view nodes
* view autoscaling

## backplane-acs-admins-project: `(^redhat-acs-fleetshard$|^rhacs$|^rhacs-.*)`
- ACS team needs read/list/watch access to core `redhat` and `rhacs` objects within their namespaces.
- Permisions at namespace scope.

* get centrals
* get stackrox
* get secureclusters
* get pod logs
* get configmaps
* view network policies
* scale machinesets
* view monitoring
* get routes
* get deployments
* get pods
* scale prometheus
* view jobs

Examples, see [srep](srep).