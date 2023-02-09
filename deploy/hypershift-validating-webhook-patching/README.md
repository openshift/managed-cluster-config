# About the validating-webhook-patching-job

This policy used to deploy a cronjob to the hosted control plane namespaces
on management cluster.

The cronjob is going to patch the validatingWebhookConfiguration custom resources
which intended to be deployed to the hosted clusters.

As the caBundle is a required field for the validatingwebhook and the validation admission
happened on the management cluster API server. We need to use the caBundle from the management
cluster in the hosted cluster validatingwebhook CR.

This is a temporary solution before we can handle the cabundle replacement within the cluster
deployment by hypershift.

## WebhookConfigurations
The following webhook configurations will be updated by this job.
- sre-regular-user-validation
- sre-namespace-validation
- sre-scc-validation
- sre-techpreviewnoupgrade-validation

## Resources included in the policy

A policy to deploy the required resources to the hosted control plane namespaces.

A placementrule to target the management cluster for the policy deployment.

A placementbinding to map the policy and the placementrule.

## Resources included in the policy
- service account
- role
- rolebinding
- cronjob

# About the managed-cluster-validating-webhooks
https://github.com/openshift/managed-cluster-validating-webhooks