# Managed Upgrade Operator Config

## Background

Based on the findings in [OSD-6330](https://issues.redhat.com/browse/OSD-6330) and [OSD-6690](https://issues.redhat.com/browse/OSD-6690), there was a proposal to split the existing configmap into separate files based on Openshift version such that SRE can have better control over which alerts to (un)silence for a specific version of Openshift. Each silenced alert needs to have associate Jira/BZ tracking number with it for reference.

## Summary

Following is the reference for alert silence in different OCP versions:

|      Alert      | Reference |       4.5     | 4.6    | 4.7 | 4.8 |
| :-------------: |:---------:|:-------------:| :-----:|:----:|:---:|
| etcdMembersDown |  OSD-6138 | Silenced | Removed | Removed | Removed |
| ClusterOperatorDown | OSD-6330 | Silenced | Silenced | Silenced | Removed|
| ClusterOperatorDegraded | OSD-6330 | Silenced | Silenced | Silenced | Removed|
| CloudCredentialOperatorDown | BZ 1889540 | Silenced | Silenced | Removed | Removed |

## CHANGELOG
* October 5th 2021
    * ClusterOperatorDown alert silence removed from 4.8 ([OSD-7890](https://issues.redhat.com/browse/OSD-7890))
    * ClusterOperatorDegraded alert silence removed from 4.8 ([OSD-7890](https://issues.redhat.com/browse/OSD-7890))
* March 15th 2021
    * etcdMembersDown alert applied only for 4.5
    * CloudCredentialOperatorDown alert applied only for 4.7
    * ClusterOperatorDown alert silence maintained for 4.5, 4.6, 4.7
    * ClusterOperatorDegraded alert silence maintained for 4.5, 4.6, 4.7
    * KubeDeploymentReplicasMismatch alert silence removed
    * MachineWithNoRunningPhase alert silence removed
