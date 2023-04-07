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

The following guidelines must be followed when submitting PR's that affect backplane resources.
Where possible these guidelines are enforced by CI and can be tested locally by running `make enforce-backplane-rules`

| Related Resources  | Description | Exceptions | Enforced by CI |
| ------------------ | ----------- | ---------- | -------------- |
| Roles/ClusterRoles | ClusterRole names must be suffixed with `-project` for namespace scoped permissions and `-cluster` for cluster scoped permissions. | `-aggregate`, `backplane-impersonate-cluster-admin` | :heavy_check_mark: |
| Roles/ClusterRoles | API Groups, resources, verbs, and namespace/resource names must be explicitly defined without using glob patterns (where applicable). | apiGroups: `tekton.dev`, `logging.openshift.io`, `velero.io` | :heavy_check_mark: |
| Roles/ClusterRoles | View access is generally permitted in `redhat-` and `openshift-` prefixed namespaces. | `openshift-backplane-cluster-admin` | :x: |
| Roles/ClusterRoles | ClusterRoles must not include permission to get/list/watch Secrets in any namespace. | N/A | :x: |
| Roles/ClusterRoles | All other access (non-read) must be justified by referencing a documented need (bug or missing capability). | N/A | :x: |
| Roles/ClusterRoles | Access that would allow bypassing RBAC cannot be granted e.g. creating/execing into pods which have access to the default service account for a namespace. | N/A | :x: |
| SubjectPermissions | SubjectPermissions must only permit ClusterRoles with `-cluster` suffix in clusterPermissions (cluster scope). | Roles: `admin`, `dedicated-readers`, `view`, `system:openshift:cloud-credential-operator:cluster-reader` | :heavy_check_mark: |
| SubjectPermissions | SubjectPermissions must only permit ClusterRoles with `-project` suffix in permissions (namespace scope). | Roles: `admin`, `dedicated-readers`, `view`, `system:openshift:cloud-credential-operator:cluster-reader` | :heavy_check_mark: |
| SubjectPermissions | SubjectPermissions allowed namespace regex must constrain bindings to only the subset of namespaces access is required in. | N/A | :x: |
| SubjectPermissions | SubjectPermissions must deny the `openshift-backplane-cluster-admin` namespace. | N/A | :heavy_check_mark: |
| Config.yaml        | RBAC for Layered Products teams is only provisioned on clusters where the respective Layered Products are installed. | N/A | :x: |


