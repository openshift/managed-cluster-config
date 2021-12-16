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

## TIMEOUT WINDOW UPGRADE PROCESS
### In reference to OSD-8643, the expected upgrade control plane duration window for MUO was changed from 90 to 120 minutes.
For SREs to re-evaluate the window timings in future, the following steps can be taken:
 * Reach out to **CCX** team, clearly mentioning the requirements.
 * The **CCX** team will auccordingly guide about accessing the data depending on the team's current status of providing data access to   someone out of CCX team.
 * The data provided by **CCX** (mostly the Jupyter notebook) will help in analysis of potential and suitable window timings for the upgrade timeout.
 * Once the timing has been finalised, upgrade the same on https://github.com/openshift/managed-cluster-config/blob/master/deploy/managed-upgrade-operator-config/10-managed-upgrade-operator-configmap.yaml
 * After successful upgradation and verification in staging environment, follow the steps on https://github.com/openshift/ops-sop/blob/master/v4/howto/push_operators_to_production.md to finally push the change to production environment.
