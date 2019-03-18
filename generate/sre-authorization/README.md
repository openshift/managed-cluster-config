This directory contains a script to create the `osd-sre-admin` ClusterRole.  Historically SRE have used `cluster-admin` role to support a cluster.  With OSD 4.x we need to limit some things SRE can do.  This is accomplished by creating a new ClusterRole with permission to everything *except* the few things we need blacklisted.

This script was created to allow generation of the ClusterRole based on an active cluster's API.  Therefore you need to be logged into a cluster in order to use it and muts have permission to interact with the API.

To generate the ClusterRole simply run `make` in this directory.

The permissions SRE are not allowed to have are managed in `blacklist.json`.
