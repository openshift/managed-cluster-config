# HCP team on management-cluster

label selectors:
* ext-hypershift.openshift.io/cluster-type == "management-cluster"
* api.openshift.com/fedramp != "true"

Applies only to ROSA HCP Management Clusters.

## backplane-readers-cluster: `cluster`

TODO: needed an "entry-level" cluster-wide role. This one looks promising, though might be too permissive.

## dedicated-readers: `(^hypershift$|^ocm-.*)`

HCP team needs read/list/watch access to a standard "base" set of k8s objects within their namespaces.

`dedicated-readers` was chosen as it provides access to objects like pods, configmaps, services, etc.

## hypershift-readers: `(^hypershift$|^ocm-.*)`

HCP team needs access to objects used by hypershift internally. This role provides that access.

Role itself is owned by the hypershift-operator itself and provides read/list/watch access to the following api groups:
- hypershift.openshift.io – objects like HostedCluster, HostedControlPlane, NodePool
- cluster.x-k8s.io – objects like MachinePool, MachineSet
- infrastructure.cluster.x-k8s.io – objects like AWSMachine, AWSCluster
- work.open-cluster-management.io – AppliedManifestWork

