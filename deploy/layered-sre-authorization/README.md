Quick readme, it could use some attention...


The layout of this directory is anything generic is in the top level.  Each sub-directory is a layered product.

In the top level we have:
- config.yaml: applys SelectorSyncSet if ANY CSSRE supported addon is installed. (each addon must update the config to be included!)
- Group - layered-cs-sre-admins: the Group for CSSRE team
- ClusterRole - backplane-cssre-admins-cluster: the ClusterRole aggregating RBAC for CSSRE at cluster scope
- ClusterRoleBinding - layered-cs-sre-admins: binding the above Group and ClusterRole
- Group - layered-sre-cluster-admins: the Group for CSSRE privilege elevation
- ClusterRoleBinding - layered-sre-cluster-admins: binding the layered-sre-cluster-admins to cluster-admin ClusterRole

In each addon sub dir (i.e. `rhmi` and `rhoam`):
- ClusterRole for "cluster" scope RBAC.
  - Aggregated to ClusterRole `backplane-cssre-admins-cluster` by use of label `managed.openshift.io/aggregate-to-cssre-admins: "cluster"`
- ClusterRole for "project" scope RBAC.
- SubjectPermission using the "project" ClusterRole to create RoleBindings in target Namespaces.

To avoid duplication, The following files are symlinked from the corresponding file in the backplane directory:

| File  | Relative Symbolic Link   |
|---    |                       ---|
| 01-layered-cssre-admins-cluster.ClusterRole.yaml  | ../backplane/cssre/01-cssre-admins-cluster.ClusterRole.yaml  |
| rhmi/01-rhmi-cssre-admins-aggregate-cluster.ClusterRole.yaml | ../../backplane/cssre/rhmi/01-rhmi-cssre-admins-aggregate-cluster.ClusterRole.yaml  |
| rhmi/ 01-rhmi-cssre-admins-project.ClusterRole.yaml| ../../backplane/cssre/rhmi/01-rhmi-cssre-admins-project.ClusterRole.yaml  |
| rhoam/01-rhoam-cssre-admins-aggregate-cluster.ClusterRole.yaml | ../../backplane/cssre/rhoam/01-rhoam-cssre-admins-aggregate-cluster.ClusterRole.yaml  |
| rhoam/01-rhoam-cssre-admins-project.ClusterRole.yaml | ../../backplane/cssre/rhoam/01-rhoam-cssre-admins-project.ClusterRole.yaml  |
| config.yaml | ../backplane/cssre/config.yaml|
| rhmi/config.yaml | ../../backplane/cssre/rhmi/config.yaml |
| rhoam/config.yaml | ../../backplane/cssre/rhoam/config.yaml |

Please edit the source files if you would like to make changes to any of the files listed above
