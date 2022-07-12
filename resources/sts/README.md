# How STS works - high level

When a customer creates a STS cluster via the ROSA CLI it now queries an API for required IAM policies for the Y stream install. The API provided by Clusters Service watches for changes in [this](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/ocm/shared-resources/common.yml) file. When this file changes a new [ConfigMap](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/resources/services/ocm/aws-sts-policies.configmap.yaml) is templated which Clusters Service pods (OCM) will read.

## How to update STS

When policies and/or permissions need to be updated, execute the following. 

1. Create a PR to this repo with the desired changes to the policies. 
2. Once merged, Create an MR to [Cluster Services](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/ocm/shared-resources/common.yml#L19) to update the referenced commit hash to consume new changes. 
3. Cluster service will restart pods automatically making policy changes available almost immediately.