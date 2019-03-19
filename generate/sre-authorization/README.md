# What is this?

This directory contains a script to create the `osd-sre-admin` ClusterRole.  Historically SRE have used `cluster-admin` role to support a cluster.  With OSD 4.x we need to limit some things SRE can do.  This is accomplished by creating a new ClusterRole with permission to everything *except* the few things we need blacklisted.

This script was created to allow generation of the ClusterRole based on an active cluster's API.  Therefore you need to be logged into a cluster in order to use it and muts have permission to interact with the API.

# How is it used?

1. login as kubeadmin (or a cluster-admin) on the target cluster
2. run the `make` command
3. review changes, update `blacklist.json` if needed, repeat
4. commit changes and create PR

# When is it used?

This should only be used if the APIs available in a cluster change and the new permissions are required by SRE for day-to-day support.

Examples:

- updates to alpha (unstable) API
- new CRDs (from new operator, updated operator, new OCP release, etc)

# Who does this?

Someone on SRE whenever a change lands that requires updated permissions.
