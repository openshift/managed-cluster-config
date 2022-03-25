References:
* [BZ 2062798](https://bugzilla.redhat.com/show_bug.cgi?id=2067978)
* [Temporary fix for BZ 2067978](https://issues.redhat.com/browse/OHSS-11084)

Clusters that upgraded from 4.7 to 4.8.fc(.<2) can result in a node-resolver daemonset with an ownerReference set. This can trigger a race condition that blocks upgrades from completing as they get stuck on the dns clusteroperator.

A workaround solution is to delete the node-resolver daemonset and let it be recreated with the ownerReference.
