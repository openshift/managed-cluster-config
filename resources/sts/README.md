# How STS works - high level

When a customer creates a STS cluster via the ROSA CLI it now queries an API for required IAM policies for the Y stream install. The API provided by Clusters Service watches for changes in [this](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/ocm/shared-resources/common.yml) file. When this file changes a new [ConfigMap](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/resources/services/ocm/aws-sts-policies.configmap.yaml) is templated which Clusters Service pods (OCM) will read.

## How to update STS

When policies and/or permissions need to be updated, execute the following. 

1. Create a PR to this repo with the desired changes to the policies. 
2. Once merged, Create an MR to [Cluster Services](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/ocm/shared-resources/common.yml#L19) to update the referenced commit hash to consume new changes. 
3. Cluster service will restart pods automatically making policy changes available almost immediately.

## `sts_ocm_no_console_permission_policy` (clusters-service contract)

The policy document `sts_ocm_no_console_permission_policy.json` must stay **byte-for-byte aligned** with the same file under clusters service, [`configs/policies/sts_ocm_no_console_permission_policy.json`](https://gitlab.cee.redhat.com/service/uhc-clusters-service/-/blob/master/configs/policies/sts_ocm_no_console_permission_policy.json) in `uhc-clusters-service`. That service uses policy ID `sts_ocm_no_console_permission_policy` (see `StsOcmNoConsolePermissionPolicyID` in `pkg/aws/stshelper.go`), classifies it as an OCM role policy in `pkg/config/aws/sts_policy_loader.go`, and exposes it on the STS policies inquiry API when the `sts-ocm-no-console-permission-policy` feature toggle is enabled.

Add an identical copy under every OpenShift Y-stream directory still supported by clusters service (for example `resources/sts/4.10/` through `resources/sts/4.22/`). This policy is **not tied to a specific OpenShift version**: customers are not required to change their OCM role when it is added, and existing OCM roles remain valid.

## Managed Policies for HCP
Unlike classic deployments, managed policies for HCP are not versioned. They are stored under the `resources/sts/hypershift` directory. When updating managed policies, you must submit a PR with your changes to this folder before submitting any request to AWS. The managed policy names correspond to roles in AWS and can be found in any AWS account by searching for ROSA-prefixed policies in IAM.