# Backplane RBAC
This directory is focused around managing roles for backplane users based on their team. The goal is to maintain least access privileges.

| Directory  | Description   |
|---|---|
| cee  | RBAC for users from CEE  |
| cssre  | RBAC for SRE managing layered products or add-ons in OSD clusters. This has subdirectories for each available add-on |
| elevated-sre | RBAC for cluster admin. Used as an elevation strategy for break-glass   |
| mtsre  | RBAC for the Managed Tenants SRE team, which manages layered products or add-ons in OSD clusters. This has subdirectories for each available add-on |
| lpsre | RBAC for SRE Layered Products team (Combining of CS and MT SRE teams) |
| srep  | RBAC for SRE Platform team  |
| mkrts | RBAC for RTS team |

## Guidelines

- ClusterRole names must be suffixed with `-project` for namespace scoped permissions and `-cluster` for cluster scoped permissions.
- ClusterRoles must not include permission to get/list/watch Secrets in any namespace.
- SubjectPermissions must only permit ClusterRoles with `-cluster` suffix in clusterPermissions (cluster scope).
- SubjectPermissions must only permit ClusterRoles with `-project` suffix in permissions (namespace scope).
- SubjectPermissions allowed namespace regex must constrain bindings to only the subset of namespaces access is required in.
- SubjectPermissions must deny the `openshift-backplane-cluster-admin` namespace.
- API Groups, resources, verbs, and namespace/resource names must be explicitly defined without using glob patterns (where applicable).
- View access is generally permitted in `redhat-` and `openshift-` prefixed namespaces.
- All other access (non-read) must be justified by referencing a documented need (bug or missing capability).
- Access that would allow bypassing RBAC cannot be granted e.g. creating/execing into pods which have access to the default service account for a namespace.
- RBAC for Layered Products teams is only provisioned on clusters where the respective Layered Products are installed.
