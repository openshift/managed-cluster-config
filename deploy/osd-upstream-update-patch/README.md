https://issues.redhat.com/browse/OSD-6746

# Overview

This patch (re-)introduces the `upstream` field into the `clusterversion` CR.

This field has been removed as a default setting in `clusterversion` in OCP 4.7, meaning that `managed-upgrade-operator` no longer has a source for retrieving the upstream URL. [0]

The managed-upgrade-operator uses the upstream field in the cluster's clusterversion CR to validate that a valid edge exists in Cincinnati between the FROM and TO versions of the cluster's upgrade policy.

The `managed-upgrade-operator` performs the Cincinnati validation as a failsafe check to ensure that an edge has not been pulled in the time between an upgrade policy being scheduled and the time that the upgrade commences. It cannot rely on the `clusterversion`'s `availableUpdates` information to perform this validation when performing a Y-Stream upgrade, as the edge will not appear in `availableUpdates` without the cluster being on the new Y-Stream channel.

As an interim measure, the field is being explicitly set in OSD clusters. A Bugzilla has been raised to work through this issue long-term. [1]

# References

[0] https://github.com/openshift/installer/pull/4112
[1] https://bugzilla.redhat.com/show_bug.cgi?id=1939755
