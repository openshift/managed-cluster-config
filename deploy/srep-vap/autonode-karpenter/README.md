# Validating Admission Policies for AutoNode (Karpenter)

## Purpose
Enforces security baselines on Karpenter `NodePool` and `OpenshiftEC2NodeClass` resources on ROSA HCP clusters with AutoNode enabled. Deployed via ACM to HCP clusters 4.21+.

## Enforcements

### NodePool (`karpenter.sh/v1`)
- Block tiny instance types (`.nano`, `.micro`, `.small`, `.medium`)
- Block reserved node-role labels (`master`, `infra`, `control-plane`)

### NodeClaim (`karpenter.sh/v1`)
- Block tiny instance types (`.nano`, `.micro`, `.small`, `.medium`) selected by Karpenter at provisioning time

### OpenshiftEC2NodeClass (`karpenter.hypershift.openshift.io/v1beta1`)
- EBS volume size >= 100Gi
- EBS encryption required
- Block reserved tags (`red-hat-managed`, `api.openshift.com/*`, `kubernetes.io/cluster/*`)
- Block public IP association
