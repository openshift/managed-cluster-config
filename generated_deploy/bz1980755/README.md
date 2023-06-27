# bz1980755

## About

This sets up a `CronJob` on the cluster which aims to detect and remediate any SRE operators that are impacted by BZ [1980755](https://bugzilla.redhat.com/show_bug.cgi?id=1980755).

An operator which is impacted by this issue:
- Will have a `ConstraintsNotSatisfied` Subscription status
- Will no longer update to any future versions whilst impacted.

The fix of the CronJob is to:
- Remove the impacted `Subscription` and any associated `InstallPlans` and `ClusterServiceVersions`
- Reinstall the `Subscription` (minus the `last-applied-configuration` annotation which would otherwise break ClusterSyncs)

The CronJob only acts on operators installed into managed namespaces.

## References:
* [BZ 1980755](https://bugzilla.redhat.com/show_bug.cgi?id=1980755)
