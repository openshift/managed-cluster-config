# Managed Resources ConfigMap

The included `get-managed-resources.sh` script collects a list of hive-managed resources from a cluster and generates a configmap containing a yaml file that lists out each resource.
This script should be run periodically to produce an up-to-date reference of all hive-managed resource in a cluster.

## Requirements

* `jq`
* `pip install oyaml` 

## Instructions to update the ConfigMap

* Ensure you are logged into an OSD cluster
* Run the `get-managed-resources.sh` script
* Once the script has completed, raise a PR to commit the updated configmap back into managed-cluster-config.
