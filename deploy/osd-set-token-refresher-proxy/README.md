# Setting cluster-wide proxy for token-refresher

This sets up a CronJob to monitor the state of the cluster's cluster-wide proxy and apply appropriate environment variables to the `token-refresher` job to allow it to use the proxy.

If the cluster is not configured with a proxy, the environment variables in the `token-refresher` will be set with an empty value which will have the same effect as not using a proxy at all.
