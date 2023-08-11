# HCP team on management-cluster

label selectors:
* ext-hypershift.openshift.io/cluster-type == "management-cluster"
* api.openshift.com/fedramp != "true"

Applies only to ROSA HCP Management Clusters.

## dedicated-readers: `(^hypershift$|^ocm-.*)`

HCP team needs read/list/watch access to core k8s and ocp objects within their namespaces.

HCP team also needs access to objects used by hypershift internally, which is provided by `hypershift-readers`, a role that's aggregated into `dedicated-readers`.

The hypershift role is owned by the hypershift-operator itself and provides read/list/watch access to the following api groups:
- hypershift.openshift.io – objects like HostedCluster, HostedControlPlane, NodePool
- cluster.x-k8s.io – objects like MachinePool, MachineSet
- infrastructure.cluster.x-k8s.io – objects like AWSMachine, AWSCluster
- work.open-cluster-management.io – AppliedManifestWork

