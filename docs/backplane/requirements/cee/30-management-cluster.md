# CEE on OSD/ROSA

label selectors:

- managed=true (implied)
- ext-hypershift.openshift.io/cluster-type=management-cluster

These permissions only apply to the following products:

- OSD (Specifically Management Clusters)

## openshift-backplane-cee: `cluster`

These clusterPermissions are available at the cluster scope:

- view
- backplane-cee-management-cluster-cluster

* view is a k8s-native set of permissions that grants read-only access to all kubernetes-native objects.
* backplane-cee-management-cluster-cluster is a set of permissions that grants read-only access to hypershift management-cluster specific resources.
