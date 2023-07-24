# SREP on hive shard
label selector:
* ext-managed.openshift.io/hive-shard == "true"
* api.openshift.com/fedramp != "true"

Applies only to hive shards.

## backplane-srep-hive-project: `(^uhc-.*)`
Permission to manage hive resources.
* patch clusterdeployment
* delete clusteresync (force re-sync)

## dedicated-readers: `(^hive$|^backplane$|^uhc-.*|^.*-operator$)`
Read access to additional namespaces on a hive shard.
