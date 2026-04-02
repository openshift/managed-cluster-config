# ROSA Karpenter Controller Managed Policy Justification

## Overview

This document provides detailed justification for each permission in the ROSA Karpenter Controller managed policy. ROSA Karpenter Controller is an automatic node provisioning and scaling feature for Red Hat OpenShift Service on AWS (ROSA) clusters, similar to Karpenter functionality but integrated with ROSA's security model and operational patterns.

## Security Model

The ROSA Karpenter Controller policy follows the established ROSA security patterns:

- **Primary boundary**: Service-specific tagging using `red-hat-managed: "true"`
- **Resource creation**: Requires appropriate request tags for new resources
- **Resource modification**: Requires existing resource tags for managed resources
- **Combined operations**: Uses both request and resource tag conditions where appropriate

## Permission Groups and Justifications

### ReadPermissions

**Actions**: `ec2:Describe*`
**Resource**: `*`
**Justification**: Karpenter Controller requires comprehensive read access to understand the AWS environment for node placement decisions. These read-only operations are essential for:
- Discovering available instance types and pricing
- Understanding network topology (VPCs, subnets, security groups)
- Making informed scaling decisions based on resource availability

**Security**: Read operations pose minimal security risk and do not modify infrastructure.

### SSMReadActions

**Actions**: `ssm:GetParameter`
**Resource**: `arn:aws:ssm:*::parameter/aws/service/*`
**Justification**: Required to access AWS-managed SSM parameters containing official AMI IDs for different instance types and regions. This ensures Karpenter Controller uses only validated, supported AMIs for ROSA worker nodes.

**Security**: Limited to AWS service parameters only, preventing access to customer SSM parameters.

### PricingReadActions

**Actions**: `pricing:GetProducts`
**Resource**: `*`
**Justification**: Enables cost-aware node provisioning by accessing AWS pricing information. Karpenter Controller can make optimal instance selection decisions based on cost considerations and spot instance pricing.

**Security**: Pricing service is global and read-only, posing no security risk.

### KMSPermissions

**Actions**: `kms:DescribeKey`, `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`
**Resource**: `*`
**Justification**: Required for EBS volume encryption when customers specify customer-managed KMS keys for node storage encryption. Karpenter Controller needs to encrypt volumes during instance creation and access encrypted volumes for node operations.

**Security**: Standard KMS operations for volume encryption. No administrative permissions like key creation or deletion.

### KMSGrantPermissions

**Actions**: `kms:CreateGrant`, `kms:ListGrants`, `kms:RevokeGrant`
**Resource**: `*`
**Condition**: `kms:GrantIsForAWSResource: "true"`
**Justification**: Enables Karpenter Controller to create KMS grants for AWS services (like EC2) to use customer-managed keys for EBS volume encryption. Grants allow services to perform cryptographic operations on behalf of the principal.

**Security**: Grant operations are restricted to AWS resources only through the condition, preventing grants to external principals.

### CreateEC2Resources

**Actions**: `ec2:RunInstances`, `ec2:CreateFleet`
**Resources**: Security groups, subnets, capacity reservations
**Justification**: Core functionality for launching EC2 instances and creating fleets for automated node provisioning. These resources are prerequisite dependencies for instance creation.

**Security**: Limited to specific resource types needed for instance creation. No conditions required as these are prerequisite resources.

### CreateEC2ResourcesWithApprovedAMIs

**Actions**: `ec2:RunInstances`, `ec2:CreateFleet`
**Resource**: `arn:aws:ec2:*::image/*`
**Condition**: `ec2:Owner`: `"531415883065"`, `"251351625822"`, `"210686502322"`
**Justification**: Allows Karpenter Controller to launch instances using only approved ROSA AMIs from trusted publisher accounts. These owner accounts represent Red Hat and AWS official AMI publishers for ROSA-compatible images.

**Security**: Strict AMI access control prevents use of unauthorized or potentially compromised images. Only Red Hat and AWS-approved AMIs can be used for node provisioning, maintaining ROSA security standards.

### CreateEC2ResourcesWithTags

**Actions**: `ec2:RunInstances`, `ec2:CreateFleet`, `ec2:CreateLaunchTemplate`
**Resources**: Fleets, instances, volumes, network interfaces, launch templates, spot requests
**Condition**: `aws:RequestTag/red-hat-managed: "true"`
**Justification**: Primary Karpenter Controller operations for creating managed infrastructure. The ROSA service boundary is enforced through required tagging.

**Security**: Service boundary enforced through mandatory `red-hat-managed: "true"` request tag. Only resources with proper tagging can be created.

### CreateEC2ResourcesLaunchTemplate

**Actions**: `ec2:RunInstances`, `ec2:CreateFleet`
**Resource**: `arn:aws:ec2:*:*:launch-template/*`
**Condition**: `aws:ResourceTag/red-hat-managed: "true"`
**Justification**: Allows Karpenter Controller to use existing ROSA-managed launch templates for consistent node provisioning. Launch templates ensure standardized configuration across all managed nodes.

**Security**: Scoped to ROSA-managed launch templates only through resource tag condition.

### CreateTagsOnResources

**Actions**: `ec2:CreateTags`
**Resources**: Fleets, instances, volumes, network interfaces, launch templates, spot requests
**Conditions**: 
- `ec2:CreateAction`: Limited to creation actions
- `aws:RequestTag/red-hat-managed: "true"`
**Justification**: Essential for maintaining service boundaries and resource ownership. Tags enable proper resource lifecycle management and cost allocation.

**Security**: Tagging restricted to resource creation time and requires ROSA management tag.

### ManageTagsOnManagedResources

**Actions**: `ec2:CreateTags`
**Resource**: `arn:aws:ec2:*:*:instance/*`
**Condition**: `aws:ResourceTag/red-hat-managed: "true"`
**Justification**: Allows updating tags on existing managed instances for cluster integration, lifecycle management, and operational metadata. This enables Karpenter Controller to add labels, annotations, and other operational tags as needed for cluster functionality.

**Security**: Restricted to ROSA-managed instances only through resource tag condition. Tag key restrictions have been relaxed to allow operational flexibility while maintaining service boundary through the red-hat-managed tag requirement.

### TerminateManagedResources

**Actions**: `ec2:TerminateInstances`, `ec2:DeleteLaunchTemplate`
**Resources**: Instances, launch templates
**Condition**: `aws:ResourceTag/red-hat-managed: "true"`
**Justification**: Required for scaling down operations and resource cleanup when demand decreases or nodes become unhealthy.

**Security**: Service boundary enforced through resource tag condition. Only ROSA-managed resources can be terminated.

### PassInstanceRole

**Actions**: `iam:PassRole`
**Resource**: `arn:aws:iam::*:role/*`
**Condition**: `iam:PassedToService`: `ec2.amazonaws.com`, `ec2.amazonaws.com.cn`
**Justification**: Required to attach IAM roles to EC2 instances for node functionality. Nodes need IAM permissions to interact with AWS services and join the cluster.

**Security**: PassRole is limited to EC2 service only, preventing privilege escalation to other services.

### ManageInstanceProfiles

**Actions**: `iam:CreateInstanceProfile`, `iam:TagInstanceProfile`, `iam:AddRoleToInstanceProfile`, `iam:RemoveRoleFromInstanceProfile`, `iam:DeleteInstanceProfile`
**Resource**: `arn:aws:iam::*:instance-profile/*`
**Condition**: `aws:RequestTag/red-hat-managed: "true"`
**Justification**: Karpenter Controller needs to create and manage instance profiles dynamically for different node configurations and scaling scenarios.

**Security**: Service boundary enforced through required ROSA management tag on new instance profiles.

### ManageInstanceProfilesExisting

**Actions**: `iam:TagInstanceProfile`, `iam:AddRoleToInstanceProfile`, `iam:RemoveRoleFromInstanceProfile`, `iam:DeleteInstanceProfile`
**Resource**: `arn:aws:iam::*:instance-profile/*`
**Condition**: `aws:ResourceTag/red-hat-managed: "true"`
**Justification**: Management operations on existing ROSA-managed instance profiles for role updates and cleanup.

**Security**: Limited to existing ROSA-managed instance profiles through resource tag condition.

### ReadInstanceProfiles

**Actions**: `iam:GetInstanceProfile`, `iam:ListInstanceProfiles`
**Resource**: `*`
**Justification**: Required to validate instance profile configurations and discover existing profiles for reuse.

**Security**: Read-only operations pose minimal security risk.

### InterruptionQueueActions

**Actions**: `sqs:DeleteMessage`, `sqs:GetQueueUrl`, `sqs:ReceiveMessage`
**Resource**: `*`
**Justification**: Enables Karpenter Controller to respond to EC2 spot instance interruption notifications and scheduled maintenance events for graceful node draining and replacement. Customers are expected to create and configure the SQS queues for interruption handling.

**Security**: Read and message consumption operations on customer-managed SQS queues. No queue creation or configuration permissions granted.

## Integration with Existing ROSA Services

This policy is designed to complement existing ROSA managed policies:

- **ROSAKubeControllerPolicy**: Handles load balancer and security group management
- **ROSANodePoolManagementPolicy**: Manages static node pools and instance lifecycle
- **ROSAInstallerPolicy**: Handles cluster installation and initial configuration

The Karpenter Controller policy focuses specifically on dynamic, automatic node provisioning while maintaining consistency with ROSA's security patterns and service boundaries.

## Operational Context

ROSA Karpenter Controller operates as a cluster component with the following workflow:
1. Monitors cluster resource demands and node availability
2. Makes provisioning decisions based on workload requirements
3. Creates EC2 instances using standardized launch templates
4. Configures instances with appropriate IAM roles and tagging
5. Integrates nodes into the cluster through standard Kubernetes mechanisms
6. Handles scaling down and resource cleanup when demand decreases
7. Responds to interruption events for graceful node replacement

All operations maintain the `red-hat-managed: "true"` tag as the primary service boundary, ensuring clear separation between ROSA-managed and customer-owned infrastructure.