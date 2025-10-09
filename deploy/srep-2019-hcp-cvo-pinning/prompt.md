# Implementation Prompt for HCP CVO Pinning

This directory will have all the resources needed to run a CronJob on service clusters, patching manifestwork objects
with a specific annotation to override the cluster-version-operator image for a HyperShift cluster.

## Replacement Process
Build the following:

* A YAML file where we define an x.y.z version of a cluster, and a resulting image to use as an override
  * For example, 4.18.7 should use image foo:bar
* A python script (ideally without dependencies) that does the following (use patch.sh as your example for the logic):
  * Iterates over managedclusters
  * Decides if they need to have the override annotation added, based on the YAML file you created previously
    * Decides if the override annotation should be removed if it was previously needed (ie the cluster has upgraded out of the effected version)
  * Adds or removes the annotation by patching the manifestwork
  * The script should have good logging and error handling
  * Use `oc` for all calls to OpenShift
* The script should be wrapped in a CronJob
* The yaml and script should be stored in a ConfigMap
