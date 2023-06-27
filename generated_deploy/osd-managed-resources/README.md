# Managed Resources ConfigMap

The included `scripts/managed-resources/make-all-managed-lists.sh` script collects a list of hive-managed resources from a cluster and generates a configmap containing a yaml file that lists out all managed namespaces as well as a yaml file of ALL managed resources in `resources/managed/all-osd-resources`.
This script should be run periodically to produce an up-to-date reference of all hive-managed resource in a cluster.

## Requirements

* `pip install oyaml` 

## Instructions to update the ConfigMap

* Ensure you are logged into an OSD cluster
* Run the `scripts/managed-resources/make-all-managed-lists.sh` script
* Once the script has completed, raise a PR to commit the updated configmap and yaml back into managed-cluster-config.
