https://issues.redhat.com/browse/OSD-6053

Manage the approval for logging subscriptions but do not fight customer CICD. See job comments for details.

To pause logging operator automatic updates set configmap `osd-logging-freeze` data `freeze` to `"true"`.

To unpause logging operator automatic updates set configmap `osd-logging-freeze` data `freeze` to `"false"`.

Only applies for clusters that do have in-cluster logging support from SRE. Therefore [config.yaml](config.yaml) must match the [osd-logging/supported config.yaml](../supported/config.yaml).

# Testing

Assumes channel 4.4 is available for cluster-logging and elasticsearch operators.

1. login to a cluster that DOES NOT HAVE LOGGING ALREADY (this is destructive)
2. run test scripts

```bash
pushd deploy/osd-logging/freeze
./test.sh 2>/dev/null
popd
```

And look for any output lines starting with "FAILURE".

## No Subscriptions

1. no logging subscriptions
2. freeze=true does nothing
3. freeze=false does nothing

## Start Automatic

1. customer installs logging subscriptions, automatic
2. freeze=true moves to manual
3. freeze=false moves back to automatic

## Start Manual

1. customer installs logging subscriptions, manual
2. freeze=true does nothing
3. freeze=false does nothing

## Start Automatic, Unfrozen by Customer

1. customer installs logging subscriptions, automatic
2. freeze=true moves to manual
3. customer moves back to automatic
4. freeze=true does nothing
5. freeze=false removes annotation only
