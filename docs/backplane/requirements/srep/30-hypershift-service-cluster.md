# SREP on service-cluster
label selectors:
* ext-hypershift.openshift.io/cluster-type == "service-cluster"
* api.openshift.com/fedramp != "true"

Applies only to ROSA HCP Service Clusters.

## backplane-srep-service-cluster-cluster: `cluster`
Additional permissions at cluster scope.
* read various global OCM resources
* read hypershift resources
* read networking resources

## backplane-srep-service-cluster-project: `(^uhc.*|^ocm.*|^klusterlet.*)`
Additional permissions at project scope.
* read various namespased OCM resources
* read CAPI resources
* read cluster infrastructure resources

## dedicated-readers: `(^hypershift.*|^uhc.*|^ocm.*|^klusterlet.*|^open-cluster-management.*)`
Read access to additional HCP namespaces.

## backplane-srep-admins-project: `(^hypershift.*|^uhc.*|^ocm.*|^klusterlet.*|^open-cluster-management.*)`
Standard SREP project access to additional HCP namespaces.
https://issues.redhat.com/browse/OSD-15997
