# *CEE* for *OSD/ROSA*
label selectors:

- managed=true (implied)

These permissions allow CEE to view details required to support managed clusters. 

## openshift-backplane-cee: `(^kube$|^kube-.*|^openshift$|^openshift-.*|^default$|^redhat-.*|^rhacs$|^rhacs-*)`

These permissions are at cluster scope:

Using dedicated-readers role CEE will be able to:

get 
list
watch

resources under the mentioned namespaces. 