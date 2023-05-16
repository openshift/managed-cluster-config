# Goals

Answer the following questions:
* How can LPSRE team members proactively address backplane permissions concerns to facilitate the review process?
* What conventions should be followed to make the intention behind changes more obvious?
* Review comments are inconsistent (though not necessarily conflicting) between reviewers of backplane permissions changes. How can that be improved?
* How can we reconcile SRE-P expectations with LPSRE expectations for what constitutes reasonable permissions?

# Requirements

Backplane governs Red Hat access to both the Managed OpenShift cluster and the cloud account on which the cluster is hosted.  Permissions for each product are documented in the respective service definitions here:
* https://docs.openshift.com/dedicated/osd_architecture/osd_policy/policy-process-security.html#privileged-access_policy-process-security 
* https://docs.openshift.com/rosa/rosa_architecture/rosa_policy_service_definition/rosa-policy-process-security.html#rosa-policy-rh-access_rosa-policy-process-security

For the purposes of this document we are focusing on the in-cluster access, not the cloud account access. Since these are currently the same for OSD and ROSA (May 15, 2023) we can focus on a single set of requirements.  The following is the a summary taken from the ROSA documents and specifies only read or write operations that are something other than `None`:

* OpenShift SRE have Read permission in all core and layered product namespaces.
* OpenShift SRE have "Very limited" Write permission in core namespaces.
* CEE has Read permission in all core and layered product namespaces.

As this is written from the customer perspective and focuses on a single SRE personal there are some nuances to tease out when considering different types of support and SRE teams within Red Hat.  This document captures these nuances as guidelines.

# Guidelines

The following guidelines must be followed when submitting PR's that affect [backplane resources](../../deploy/backplane/).
Where possible these guidelines are enforced by CI and can be tested locally by running `make enforce-backplane-rules`.

In general all permissions must follow the principle of least privilege.  Meaning you only get the bare minimum permissions required to do the job, nothing more.

## Training

This guideline assumes all personas with access to production customer clusters have been through all necessary vetting (background checks) and training before access is granted.

## Access Scope

A persona must have access only to systems on which support can actively be provided by that persona.  This means if a persona is dependent on some software being installed, a layered product / addon / managed service, then the persona is not permitted access to the system until that installation is triggered.  Note this means access is not dependent on successfully deploying that software.

## Personas

| Persona | Description | References |
| ------- | ----------- | ---------- |
| Managed Cloud Service (MCS) | Customer facing support engineers (formerly Customer Experience and Engagement (CEE)) | |
| Platform SRE (SREP) | SRE in SD primarily responsible for Managed OpenShift Platform | [source page](https://source.redhat.com/groups/public/sre) |
| Layered Products SRE (LPSRE) | SRE in SD primarily responsible for Layered Products (formerly MT-SRE and CS-SRE) | [mt-sre source page](https://source.redhat.com/groups/public/sre-services/sre_services_wiki/managed_tenants_sre_introduction), [cs-sre source page](https://source.redhat.com/groups/public/sre-services/sre_services_wiki/cssre_introduction) |
| Application SRE (AppSRE) | SRE in SD primarily responsible for Red Hat internal and external SaaS offerings | [source page](https://source.redhat.com/groups/public/sre-services/sre_services_wiki/app_sre_introduction_new) |
| Hybrid SRE | Engineering teams are SRE for their products in conjunction with other SD SRE teamsl. Teams that are the initial focus include HyperShift, ACS, and ODS. | [source page](https://source.redhat.com/groups/public/sdsea/hybridsre) |

## Privilege Escalation

Some personas may elevate permissions beyond the day-to-day permisisons.  All such elevations are audited and require justification and approval from managers after use and must never be used lightly.

Personas permitted to use privilege escalation on customer clusters are:

* SREP
* LPSRE

Escalation of privileges uses a specific user to elevate permissions to `cluster-admin`.  More information on [ops-sop/v4/howto/backplane-elevate-privileges.md](https://github.com/openshift/ops-sop/blob/master/v4/howto/backplane-elevate-privileges.md).

## Day-to-Day

Permissions for day-to-day operations should not require any special permission to utilize.  These permissions follow these guidelines:

* No secret access except where the secret is known to contain no actual secret data.
* No customer namespace access as the baseline.  Customer namespace access must be justified based on specific service support needs.
* No write access by default, all write permissions require justification.
* Read access to cluster scope resources may be granted if those resources do not contain any sensitive customer data.
* Read access to namespace scoped resources is never granted at a cluster scope.
  * Exception may be granted for Red Hat managed systems only, where Red Hat is the customer, and such access is justified for day-to-day operations.
* Existing ClusterRoles are preferred when granting permissions in a namespace.
  * `view` - general read-only access to core Kubernetes and OpenShift resources, except for Secrets
  * `admin` - full administrative access to the namespace.
  * `dedicated-readers` - created by OSD/ROSA and dynamically aggregates view permissions for resources installed by OLM.

Resource specific guidelines below are enforced by CI where possible.

| Related Resources  | Description | Exceptions | Enforced by CI |
| ------------------ | ----------- | ---------- | -------------- |
| Roles/ClusterRoles | ClusterRole names must be suffixed with `-project` for namespace scoped permissions and `-cluster` for cluster scoped permissions. | `.*-aggregate`, `backplane-impersonate-cluster-admin` | :heavy_check_mark: |
| Roles/ClusterRoles | API Groups, resources, verbs, and namespace/resource names must be explicitly defined without using glob patterns (where applicable). | apiGroups: `tekton.dev`, `logging.openshift.io`, `velero.io` | :heavy_check_mark: |
| Roles/ClusterRoles | View access is generally permitted in `redhat-` and `openshift-` prefixed namespaces. | `openshift-backplane-cluster-admin` | :x: |
| Roles/ClusterRoles | ClusterRoles must not include permission to get/list/watch Secrets in any namespace. | N/A | :x: |
| Roles/ClusterRoles | All other access (non-read) must be justified by referencing a documented need (bug or missing capability). | N/A | :x: |
| Roles/ClusterRoles | Access that would allow bypassing RBAC cannot be granted e.g. creating/execing into pods which have access to the default service account for a namespace. | N/A | :x: |
| SubjectPermissions | SubjectPermissions must only permit ClusterRoles with `-cluster` suffix in clusterPermissions (cluster scope). | Roles: `admin`, `dedicated-readers`, `view`, `system:openshift:cloud-credential-operator:cluster-reader` | :heavy_check_mark: |
| SubjectPermissions | SubjectPermissions must only permit ClusterRoles with `-project` suffix in permissions (namespace scope). | Roles: `admin`, `dedicated-readers`, `view`, `system:openshift:cloud-credential-operator:cluster-reader` | :heavy_check_mark: |
| SubjectPermissions | SubjectPermissions allowed namespace regex must constrain bindings to only the subset of namespaces access is required in. | N/A | :x: |
| SubjectPermissions | SubjectPermissions must deny the `openshift-backplane-cluster-admin` namespace. | N/A | :heavy_check_mark: |
| config.yaml        | RBAC for Layered Products teams is only provisioned on clusters where the respective Layered Products are installed. | N/A | :x: |
