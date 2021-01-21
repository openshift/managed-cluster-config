https://issues.redhat.com/browse/OSD-6205

When OCP installs a cluster it sets the ClusterVerison channel to the stable for that major.minor.  So if you install a cluster using an image available only in a candidate channel the in-cluster channel is still on stable.  No upgrades will be listed available until that cluster's version is in the stable channel OR the in-cluster channel is updated.

For OSD this is a challenge as customer do not have permission to manage this directly in cluster.  OCM uses telemeter to identify the channel and available upgrades for a cluster.  Therefore to boostrap this we've created this simple set of SSS to patch the channel based on the labels on ClusterDeployments (CD).

If CD indicates it is in the fast or candidate channel we use the major.minor label to pick the right SelectorSyncSet (SSS) an patch the channel in-cluster.  This gets us the initial channel corrected.  On upgrade, OCM will create an UpgradeConfig via SyncSet that contains the new target channel.  This is then set in-cluster before the upgrade is initiated.  Once upgraded, the version and channel is fed out to telemeter.

On a minor upgrade (i.e. 4.5.z to 4.6.z) it is possible that hive will reset the channel before we get updated version information.  This is OK as the upgrade is already initiated or done and the channel is only used when assessing if an upgrade can be _started_.  Once the upgrade is complete the version is sent to telemter and ultimately is reflected in the ClusterDeployment.  This in-turn will trigger the appropriate patch from SSS created in the configuration here.

NOTE that if OCP moves to a version agnostiic channel strategy that we do not need as many of these SSS and can patch just to the channel `candidate` or `fast`.

NOTE we do not need to patch to `stable` channels, as this is the default for OCP.