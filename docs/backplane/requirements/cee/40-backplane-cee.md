# *CEE* for *OSD/ROSA*
label selectors:

- managed=true (implied)

These permissions allow CEE to view details required to support managed clusters. 

## backplane-readers-cluster: `cluster`

Existing role, permission to view select resources at cluster scope.

## backplane-cee-readers-cluster: `cluster`

* view machine configurations
* view machines
* view api request counts
* view egress ips

## openshift-backplane-cee: `(^kube$|^kube-.*|^openshift$|^openshift-.*|^default$|^redhat-.*|^rhacs$|^rhacs-*)`

* view resources in namespaces using `dedicated-readers` role

## backplane-cee-mustgather: `openshift-must-gather-operator`
Permissions to use must-gather-operator.
* create secret for mustgather
* create, delete mustgather 

## backplane-cee-pcap-collector: `openshift-backplane-managed-scripts`
Permissions to use pcap-collector managed script.
* create secret for pcap-collector

## backplane-cee: `openshift-monitoring`
Permissions to port forward from monitoring pods
* create portforward for monitoring
