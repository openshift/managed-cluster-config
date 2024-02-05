# managed-cluster-config repository

This repo contains static configuration specific to a "managed" OpenShift Dedicated (OSD) cluster.
## How to use this repo
https://issues.redhat.com/browse/SDE-2786 has change the repo slightly: /deploy holds the sources of truth, and /generated_deploy holds the configurations that will be applied by Hive.
To add a new SelectorSyncSet, add your yaml manifest to the `deploy` dir, then run the `make` command.

Alternatively you can enable GitHub Actions on your fork and `make` will be ran automatically. Additionally,
the action will create a new commit with the generated files.

To add an ACM (Governance) Policy
- If the manifest of the object you want to convert to policy already exists in `deploy` : in the object config.yaml, add a field `policy: `destination: "acm-policies"` (example: https://github.com/openshift/managed-cluster-config/blob/master/deploy/backplane/cee/config.yaml) 
- If the manifest of the object does not exist: add your manifests with a config.yaml file. If you only want this object to be deployed as Policy, see [this example](https://github.com/openshift/managed-cluster-config/tree/bad140663d088cbce06edaf2527f69651db5a80b/deploy/hs-mgmt-route-monitor-operator)

`make` will look for `config.yaml` files, runs it with the PolicyGenerator binary and save the output to `generated_deploy/acm-policies` directory. `make` will then automatically
add the policy as a new SelectorySyncSet.

# Building

## Dependencies

- oyaml: `pip install oyaml`

# Configuration

All resources in `generated_deploy/` are bundled into a template that is used by config management to apply to target "hive" clusters.  The configuration is deployed to the "hive" cluster inside a SelectorSyncSet.

SelectorSyncSet deployment supports resources that are synced down to OSD clusters.  Each are explained in detail here.  The general configuration is managed in a `config.yaml` file in each deploy directory.  Key things of note:

* This file is now mandatory in the scope of OSD-15267 and have been added to all folders. In case it is not define, `make` will fail
```
+ scripts/generate_template.py -t scripts/templates/ -y deploy -d /Users/bdematte/git/managed-cluster-config/hack/ -r managed-cluster-config
ERROR : Missing config.yaml for resource defined in deploy/acm-policies
Some config.yaml files are missing, exiting...
make: *** [generate-hive-templates] Error 1
```
* Configuration is _not_ inherited by sub-directories!  Every (EVERY) directory in the `deploy/` hierarchy must define a `config.yaml` file.

You must specify a `deploymentMode` property in `config.yaml`.

* `deploymentMode` (optional, default = `"SelectorSyncSet"`) - either "Policy" or "SelectorSyncSet".

## Direct Deployment

Direct deployments to Hive clusters should be done via [app-interface](https://gitlab.cee.redhat.com/service/app-interface#manage-openshift-resources-via-app-interface-openshiftnamespace-1yml).

## SelectorSyncSet Deployment

In the `config.yaml` file you define a top level property `selectorSyncSet`.  Within this configuration is supported for `matchLabels`, `matchExpressions`, `matchLabelsApplyMode`, `resourceApplyMode` and `applyBehavior`.

* `matchLabels` (optional, default: `{}`) - adds additional `matchLabels` conditions to the SelectorSyncSet's `clusterDeploymentSelector`
* `matchExpressions` (optional, default: `[]`) - adds `matchExpressions` conditions to the SelectoSyncSet's `clusterDeploymentSelector`
* `resourceApplyMode` (optional, default: `"Sync"`) - sets the SelectorSyncSet's `resourceApplyMode`
* `matchLabelsApplyMode` (optional, default: `"AND"`) - When set as `"OR"` generates a separate SSS per `matchLabels` conditions. Default behavior creates a single SSS with all `matchLabels` conditions.  This is to tackle a situation where we want to apply configuration for one of many label conditions.
* `applyBehavior` (optional, default: None, [see hive default](https://github.com/openshift/hive/blob/master/config/crds/hive.openshift.io_selectorsyncsets.yaml)) - sets the SelectorSyncSet's `applyBehavior`

You can also define a top level property `policy` to specify the behaviour of `./scripts/generate-policy-config.py` for the resource. Supported sub-properties :
* `complianceType` (optional, default: `"mustonlyhave"`, [see operator values](https://github.com/open-cluster-management-io/config-policy-controller/blob/main/api/v1/configurationpolicy_types.go) - select the compliance type for the policy when used by `./scripts/generate-policy-config.py`)
* `metadataComplianceType` (optional, default: `"musthave"`, [see operator values](https://github.com/open-cluster-management-io/config-policy-controller/blob/main/api/v1/configurationpolicy_types.go) - select the compliance type for metadata for the policy when used by `./scripts/generate-policy-config.py`)

Example to apply a directory for any of a set of label conditions using Upsert:
```yaml
deploymentMode: "SelectorSyncSet"
selectorSyncSet:
    matchLabels:
        myAwesomeLabel: "some value"
        someOtherLabel: "something else"
    resourceApplyMode: "Upsert"
    matchLabelsApplyMode: "OR"
policy:
    complianceType: "mustonlyhave"
    metadataComplianceType: "musthave"
```

# Selector Sync Sets included in this repo

## Prometheus

A set of rules and alerts that SRE requires to ensure a cluster is functioning.  There are two categories of rules and alerts found here:

1. SRE specific, will never be part of OCP
2. Temporary addition until made part of OCP

## Prometheus and Alertmanager persistent storage

Persistent storage is configured using the configmap `cluster-monitoring-config`, which is read by the cluster-monitoring-operator to generate PersistentVolumeClaims and attach them to the Prometheus and Alertmanager pods.

## Curated Operators

Initially OSD will support a subset of operators only.  These are managed by patching the OCP shipped OperatorSource CRs.  See `deploy/osd-curated-operators`.

NOTE that ClusterVersion is being patched to add overrides.  If other overrides are needed we'll have to tune how we do this patching.  It must be done along with the OperatorSource patching to ensure CVO doesn't revert the OperatorSource patching.

## Console Branding

In OSD, managed-cluster-config sets a [key named `branding` to `dedicated`](https://github.com/openshift/managed-cluster-config/blob/master/deploy/osd-console-branding/osd-branding.console.Patch.yaml) in the [Console operator](https://github.com/openshift/api/blob/master/operator/v1/types_console.go#L89-L135). This value is in turn read by code that applies the [logo](https://github.com/openshift/console/blob/1572a985cc0753d7e2630984c5163170765e9487/frontend/public/components/masthead.jsx) and [other branding elements](https://github.com/openshift/console/search?p=2&q=dedicated) predefined for that value.

## OAuth Templates

Docs TBA.

## Resource Quotas

Refer to [deploy/resource-quotas/README.md](deploy/resource-quotas/README.md).

## Image Pruning

Docs TBA.

# Dependencies

pyyaml


# Additional Scripts

There are additional scripts in this repo as a holding place for a better place or a better solution / process.
