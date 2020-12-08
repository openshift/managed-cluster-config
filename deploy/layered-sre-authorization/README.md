Quick readme, it could use some attention...


The layout of this directory is anything generic is in the top level.  Each sub-directory is a layered product.

In the top level we have:
- config.yaml: applys SelectorSyncSet if ANY CSSRE supported addon is installed. (each addon must update the config to be included!)
- Group - layered-cs-sre-admins: the Group for CSSRE team
- ClusterRole - backplane-cs-sre-admins-cluster: the ClusterRole aggregating RBAC for CSSRE at cluster scope
- ClusterRoleBinding - layered-cs-sre-admins: binding the above Group and ClusterRole
- Group - layered-sre-cluster-admins: the Group for CSSRE privilege elevation
- ClusterRoleBinding - layered-sre-cluster-admins: binding the layered-sre-cluster-admins to cluster-admin ClusterRole

In each addon sub dir (i.e. `rhmi` and `rhoam`):
- ClusterRole for "cluster" scope RBAC.
  - Aggregated to ClusterRole `backplane-cs-sre-admins-cluster` by use of label `managed.openshift.io/aggregate-to-layered-cs-sre-admins: "cluster"`
- ClusterRole for "project" scope RBAC.
- SubjectPermission using the "project" ClusterRole to create RoleBindings in target Namespaces.

To avoid duplication, The following files are symlinked from the corresponding file in the backplane directory:

| File  | Relative Symbolic Link   |
|---    |                       ---|
| config.yaml  |  ../backplane/layered-sre/config.yaml |
| 01-layered-cs-sre-admins-cluster.ClusterRole.yaml  | ../backplane/layered-sre/01-cs-sre-admins-cluster.ClusterRole.yaml  |
| rhmi/01-rhmi-cs-sre-admin-aggregate-cluster.ClusterRole.yaml | ../../backplane/layered-sre/rhmi/01-rhmi-cs-sre-admin-aggregate-cluster.ClusterRole.yaml  |
|  rhmi/ 01-rhmi-cs-sre-admin-project.ClusterRole.yaml| ../../backplane/layered-sre/rhmi/01-rhmi-cs-sre-admin-project.ClusterRole.yaml  |
| rhmi/config.yaml  |  ../../backplane/layered-sre/rhmi/config.yaml |
|  rhoam/01-rhoam-cs-sre-admin-aggregate-cluster.ClusterRole.yaml | ../../backplane/layered-sre/rhoam/01-rhoam-cs-sre-admin-aggregate-cluster.ClusterRole.yaml  |
| rhoam/01-rhoam-cs-sre-admin-project.ClusterRole.yaml | ../../backplane/layered-sre/rhoam/01-rhoam-cs-sre-admin-project.ClusterRole.yaml  |
| rhoam/config.yaml  |  config.yaml |

Please edit the source files if you would like to make changes to any of the files listed above