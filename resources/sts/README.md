# How STS works - high level

When a customer creates a cluster via the rosa cli it now queries an API for required policies and permissions for the Y stream install. The API is provided by Clusters Services consuming this repo. 

## How to update STS

When policies and/or permissions need to be updated, execute the following. 

1. Create a PR to this repo with the desired changes to the policies. 
2. Once merged, Create an MR to [Cluster Services](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/ocm/shared-resources/common.yml#L19) to update the referenced commit hash to consume new changes. 
3. Changes wont be made available in production until Clusters Services is promoted. This commonly occurs on Wednesdays of each week. 
