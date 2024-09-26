# *MCS Tier Two Support Engineers* for *OSD/ROSA*
label selectors:

- managed=true (implied)

These permissions allow MCS Tier Two Support Engineers to view details required to support managed clusters. 

## backplane-readers-cluster: `cluster`

Existing role, permission to view select resources at cluster scope.

## backplane-mcs-tier-two-readers-cluster: `cluster`

* view machine configurations
* view machines
* view api request counts
* view egress ips

## openshift-backplane-mcs-tier-two: `(^kube$|^kube-.*|^openshift$|^openshift-.*|^default$|^redhat-.*|^rhacs$|^rhacs-*)`

* view resources in namespaces using `dedicated-readers` role
