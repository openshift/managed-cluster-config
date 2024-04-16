# *ACS Team* for *OSD/ROSA*

Process is captured [ROX-22017: Harden Network Security API Permissions](https://docs.google.com/document/d/1lyzFjK51py6o62zS5ErPFLbCNVJfq4e5PvVI2Y2z0Mg/edit)

label selectors:
* labels
- `api.openshift.com/addon-acs-fleetshard: "true"` OR
- `api.openshift.com/addon-acs-fleetshard-qa: "true"` OR
- `api.openshift.com/addon-acs-fleetshard-dev: "true"` 

For where access is applied

These permissions are a baseline access for the ACS:CS team across OSD/ROSA infra.

## backplane-acs-admins-cluster: `cluster`
Permissions at cluster scope. 

* view projects
* get projects
* get nodes
* view oauth
* view namespaces
* view infrastructure
* view ingresscontrollers
* view dnsrecords
* view ingresses
* view networks
* view nodes
* view clusterroles and clusterrolebindings
* view customresourcedefinitions
* view pod and node metrics
* view storageclasses
* view persistentvolumes

## backplane-acs-admins-project: `(^redhat-acs-fleetshard$|^rhacs$|^rhacs-.*)`
- ACS team needs read/list/watch access to core `redhat` and `rhacs` objects within their namespaces.
- Permisions at namespace scope.

* get centrals
* get stackrox
* get secureclusters
* get pods and pod logs
* view deployments
* get deployments
* view routes
* view egress firewalls
* view roles and rolebindings
* patch persistentvolumeclaims

## backplane-acs-ingress: `openshift-ingress`

- ACS team needs get/list/watch access to inspect the routers and logs

* view deployments
* view pods
* view pod logs

## backplane-acs-monitoring: `openshift-monitoring`

- ACS team needs get/list/watch access to the openshift monitoring prometheus-related pods, statefulsets and services

* view pods
* view pods/log
* view statefulsets
* view services

## backplane-acs-rhacs-observability: `rhacs-observability`

- ACS team needs to inspect the observability resources

* view alertmanagerconfigs
* view alertmanagers
* view podmonitors
* view probes
* view prometheuses
* view prometheusrules
* view servicemonitors
* view thanosrulers
* view observabilities
* view grafanas

- ACS team needs to be able to increase the prometheus storage and restart prometheus

* patch persistentvolumeclaims
* patch statefulsets

**Note** Please update this document as addional permisions are requested, thank you.