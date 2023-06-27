# Acknowledgement of Upgrade Gates

Some versions of Openshift may require manual steps as prerequisites for a successful cluster upgrade. These pre-requirements will be formulated in form of gates that block cluster-version-operator of kicking off an upgrade.

Read more about CVO gates [here](https://github.com/openshift/enhancements/blob/mater/enhancements/update/upgrades-blocking-on-ack.md#general-implementation).

For AWS STS cluster an additional annotation on the cloud-credentials may be necessary.

This folder contains the SelectorSyncSets to sync the acknowledgment of these upgrade gates for OCP and STS to the clusters. Hive applies them based on the particular annotation of the ClusterDeployment and unblocks an upgrade.
