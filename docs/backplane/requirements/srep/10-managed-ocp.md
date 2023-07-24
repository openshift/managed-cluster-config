# SREP on OSD/ROSA
label selector:
* managed=true (implied)

These premissions are the baseline across the managed fleet and apply to all product flavors:
* OSD
* ROSA Classic
* ROSA HCP

## backlplane-srep-admins-cluster: `cluster`
Permissions at cluster scope.
* patch nodes
* get node logs
* manage projectsand namespaces
* create authn/z reviews
* delete users and identities
* view machine resources
* delete machines
* view api request counts
* view, delete, approve CSR
* view, delete vpc endpoints
* get and post to all endpoints (nonResourceURLs)

## backplane-srep-admins-project: `(^kube$|^kube-.*|^openshift$|^openshift-.*|^default$|^redhat-.*)`
Permisions at namespace scope.
* evict pods
* portforward pods
* exec pods
* create and delete jobs
* delete builds
* oc debug
* create security reviews
* resize and delete PVCs
* scale applications
* delete replicasets
* pause MHC
* scale machinesets
* scale prometheus
* delete upgradeconfig
* cleanup operators
* view monitoring
* manage velero (legacy)
* manage logging (legacy)

## backplane-srep-mustgather: `openshift-must-gather-operator`
Permissions to use must-gather-operator.
* create secret for mustgather
* create, delete mustgather 

## backplane-srep-pcap-collector: `openshift-backplane-managed-scripts`
Permissions to use pcap-collector managed script.
* create secret for pcap-collector
