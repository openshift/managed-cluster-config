Quick readme, it could use some attention...


The layout of this directory is anything generic is in the top level.  Each sub-directory is a layered product.

In the top level we have:
- config.yaml: applys SelectorSyncSet if ANY CSSRE supported addon is installed. (each addon must update the config to be included!)
- Group - layered-cs-sre-admins: the Group for CSSRE team
- ClusterRole - layered-cs-sre-admins-cluster: the ClusterRole aggregating RBAC for CSSRE at cluster scope
- ClusterRoleBinding - layered-cs-sre-admins: binding the above Group and ClusterRole
- Group - layered-sre-cluster-admins: the Group for CSSRE privilege elevation
- ClusterRoleBinding - layered-sre-cluster-admins: binding the layered-sre-cluster-admins to cluster-admin ClusterRole

In each addon sub dir (i.e. `rhmi` and `rhoam`):
- ClusterRole for "cluster" scope RBAC.
  - Aggregated to ClusterRole `layered-cs-sre-admins-cluster` by use of label `managed.openshift.io/aggregate-to-layered-cs-sre-admins: "cluster"`
- ClusterRole for "project" scope RBAC.
- SubjectPermission using the "project" ClusterRole to create RoleBindings in target Namespaces.