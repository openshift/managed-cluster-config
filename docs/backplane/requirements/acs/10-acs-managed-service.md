# *ACS Team* for *OSD/ROSA*

Process is captured [ROX-22017: Harden Network Security API Permissions](https://docs.google.com/document/d/1lyzFjK51py6o62zS5ErPFLbCNVJfq4e5PvVI2Y2z0Mg/edit)

label selectors:
* labels
- `api.openshift.com/addon-acs-fleetshard: "true"` OR
- `api.openshift.com/addon-acs-fleetshard-qa: "true"` OR
- `api.openshift.com/addon-acs-fleetshard-dev: "true"` 

For where access is applied

These permissions are a baseline acess for the ACS:CS team across OSD/ROSA infra.

## backlplane-acs-admins-cluster: `cluster`
Permissions at cluster scope. 

* view projects
* get projects
* get nodes
* view oauth
* view namespaces

## backplane-acs-admins-project: `(^redhat-acs-fleetshard$|^rhacs$|^rhacs-.*)`
- ACS team needs read/list/watch access to core `redhat` and `rhacs` objects within their namespaces.
- Permisions at namespace scope.

* get centrals
* get stackrox
* get secureclusters
* get pods and pod logs
* scale deployments

**Note** Please update this document as addional permisions are requested, thank you.