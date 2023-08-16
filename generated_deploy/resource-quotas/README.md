# Handle Resource Quotas

These Makefiles and templates are a port of the [openshift-tools](1). The purpose is to ensure basic quotas are applied to managed clusters while allowing for exemptions in certain namespaces. These exemptions are specified in `values.mk` (see Uage section).

## Usage

Running `make` will auto-generate [hive](2) `SelectorSyncSet` manifests into the same directory as the `Makefile`, these will typically be committed back to git. Various changes can be made in the `values.mk` file.

### Changing values

In `values.mk`, there are the following user-settable values:

* `PERSISTENT_VOLUME_EXCEPTIONS` - Space separated list of which namespaces are exempt from the `DEFAULT_PV_QUOTA`
* `LOAD_BALANCER_EXCEPTIONS` - Space separated list of which namespaces are exempt from the `DEFAULT_LB_QUOTA`
* `DEFAULT_PV_QUOTA` - How much space (in Gi) can be allocated for a persistent volume (PV) (Default is `100` Gi)
* `DEFAULT_LB_QUOTA` - How many load balancers (LB) may be allocated? (Default is `2`)

There are two additional values which **SHOULD NOT** be changed without significant thought and planning:

* `PV_EXCLUSION_LABEL_NAME` - Name of the label applied to the `Namespace` to exempt it from PV quotas
* `LB_EXCLUSION_LABEL_NAME` - Name of the label applied to the `Namespace` to exempt it from LB quotas 

Changing these two values may not cleanup any old labels that were in place, which may not be desired behaviour.

## Output

The Makefile generates two kinds of manifests, 1) default `ClusterResourceQuota` manifests and 2) Per-`Namespace` exemptions to those quotas. Only one manifest will be created per `Namespace`, with the appropriate patch fragment to be applied.

[1]: https://github.com/openshift/openshift-tools/tree/5e66cd7df5117ebea93ce28c0676ad8c68285981/ansible/roles/openshift_master_resource_quota "openshift-tools porting source"
[2]: https://github.com/openshift/hive "Hive project page"
