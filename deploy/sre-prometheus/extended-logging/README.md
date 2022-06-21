This folder will duplicate all of the elasticsearch alerts with SRE suffix alerts

you can also see [https://github.com/openshift/configure-alertmanager-operator/pull/224](configure-alertmanager PR) that silences the original alerts.

And [./config.yaml](config.yaml) where we specify the deployment of the alerts only to clusters that have LTS logging enabled


## file kinds
we have here 
### resources files
these are extracted from a sample cluster.

[../../../resources/prometheusrules/README.md](see the files here)

### `101-*` files
these are modified with what we got from the openshift-logging repo

these are the files we do want to deploy
### `100-*` files
these are copied from  the upper folder, should be consolidated here

this file was moved from the parent repo as it makes more sense it will stay here
