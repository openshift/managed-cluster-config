# *ACS Team* for *OSD/ROSA*

## Context

When reviewing the permissions for the ACS team, we need to consider the following:

ACS-CS runs a very small fleet of clusters for hosting all of its data-plane:
- 1 x integration
- 2 x stage
- 2 x production

The scale of the fleet will remain small for the foreseeable future.
The production clusters can already host hundreds of tenants, which is more
than enough for the current needs.

### Considerations
- The `AcsFleetShard` addon installs the resources needed to run an ACS-CS DataPlane cluster:
  - It installs `fleetshard` which is responsible for creating the tenant namespaces.
  - It installs supporting resources, such as monitoring, logging.
- The `AcsFleetShard` addon is *only* installed on those clusters. It will *never* be installed on customer clusters.
- These clusters are *only* accessible by internal staff, such as SRE and ACS-CS team members. Customers will *not* have access to these clusters.
- Each tenant gets its own namespace, `Central` instance, `Route` and DNS record.
- Tenants are only given the URL to their `Route`. They do not interact with the cluster in any other way.

Process is captured [ROX-22017: Harden Network Security API Permissions](https://docs.google.com/document/d/1lyzFjK51py6o62zS5ErPFLbCNVJfq4e5PvVI2Y2z0Mg/edit)

label selectors:
* labels
- `api.openshift.com/addon-acs-fleetshard: "true"` OR
- `api.openshift.com/addon-acs-fleetshard-qe: "true"` OR
- `api.openshift.com/addon-acs-fleetshard-dev: "true"`

For where access is applied

Permissions are applied via `backplane-acs-admins-project` SubjectPermission.

These permissions are a baseline access for the ACS:CS team across OSD/ROSA infra.  Scope of permissions are the Red Hat servers hosting ACS Central (fleetshard) and not to end-customer clusters.

## backplane-acs-admins-cluster: `cluster`
Permissions at cluster scope.

* view events
* view projects
* view nodes
* view pods
* view pod logs
* view services
* view routes
* view networkpolicies
* view deployments
* view deploymentconfigs
* view statefulsets
* view daemonsets
* view replicasets
* view replicationcontrollers
* view jobs
* view cronjobs
* view configmaps
* view poddisruptionbudgets
* view pod and node metrics
* view oauth
* view namespaces
* view operator namespaces
* view infrastructure
* view ingresscontrollers
* view dnsrecords
* view ingresses
* view networks
* view nodes
* view clusterroles, clusterrolebindings, roles and rolebindings
* view customresourcedefinitions
* view storageclasses
* view persistentvolumes
* view persistentvolumeclaims
* view volumesnapshots
* view templates
* view clustersecretstores
* view machineconfigs
* view machineconfigpools
* view machines
* view machinesets
* view machineautoscalers
* view machinehealthchecks
* view servicemonitors
* view podmonitors
* view alertmanagerconfigs
* view alertmanagers
* view probes
* view prometheuses
* view prometheusrules
* view thanosrulers
* view operator namespaces
* view clusterversions
* view clusteroperators
* view clusterserviceversions
* view subscriptions
* view catalogsources
* view operatorgroups
* view operators
* view installplans
* view olmconfigs
* view operatorconditions
* view resourcequotas
* view appliedclusterresourcequotas
* view limitranges
* view projecthelmchartrepositories
* view templates
* view horizontalpodautoscalers
* view addonoperators
* view verticalpodautoscalers
* view verticalpodautoscalercheckpoints
* view verticalpodautoscalercontrollers
* view packagemanifests
* view clusterpackages
* view clusterobjectdeployments
* view clusterobjectsets
* view clusterobjecttemplates

## backplane-acs-admins-project: `(^redhat-acs-fleetshard$|^rhacs$|^rhacs-.*|^acscs-dataplane-cd$)`
- ACS team needs read/list/watch access to core `redhat` and `rhacs` objects within their namespaces. This includes Custom Resource objects for ACS Addon.
- Permisions at namespace scope.

* view centrals
* view stackrox
* view securedclusters
* view pods and pod logs
* view services
* view deployments
* view statefulsets
* view daemonsets
* view applications
* view routes
* view egress firewalls
* view roles and rolebindings
* patch persistentvolumeclaims
* view secretstores
* view externalsecrets
* view serviceaccounts
* view securitycontextconstraints
* create pods/portforward
* create pods/exec
* delete pods
* view addons
* view addoninstance
* view addonoperators
* view packages
* view objectdeployments
* view objectsets
* view objecttemplates

## backplane-acs-openshift-ingress: `openshift-ingress`

- ACS team needs get/list/watch access to inspect the routers and logs

* view deployments
* view pods
* view pod logs

## backplane-acs-openshift-monitoring: `openshift-monitoring`

- ACS team needs get/list/watch access to the openshift monitoring prometheus-related pods, statefulsets and services

* view pods
* view pods/log
* view statefulsets
* view services
* view deployments (required for `ocm backplane console`)
* create portforwards (required for `ocm backplane console`)

## backplane-acs-openshift-console: `openshift-console`

* view deployments (required for `ocm backplane console`)

## backplane-acs-rhacs-observability: `rhacs-observability`

- ACS team needs to inspect the observability resources

* view alertmanagerconfigs
* view alertmanagers
* view podmonitors
* view probes
* view prometheuses
* view prometheusrules
* view servicemonitors
* view thanosrulers
* view observabilities
* view grafanas
* view grafanadatasources
* view grafanadashboards

- ACS team needs to be able to increase the prometheus storage and restart prometheus

* patch persistentvolumeclaims
* patch statefulsets

## backplane-acs-rhacs-secured-cluster: `rhacs-secured-cluster`

* view secrets (required for operating ACS secured cluster)

**Note** Please update this document as addional permisions are requested, thank you.
