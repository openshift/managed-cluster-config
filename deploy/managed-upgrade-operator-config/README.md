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

## Procedure to follow when silencing alerts

Important: The goal of OCP upgrades is to eventually be non-disruptive. Alerts which occur during upgrades which are a 'non-action' should be raised as OCP bugs so that silences are not necessary.

Adding alerts to the silenced list may mask real, actionable problems that could be impacting cluster health or SLA.

Before permanently updating the alert silence list, consider:

- Was SRE involvement necessary to address the alert, or did it self-resolve?
- If it self-resolved, was this alert directly caused by the cluster upgrade, or was it incidental?
- If it was caused by an upgrade, should OCP upgrade be producing this alert?
- If OCP upgrades should not be producing this alert, does a Bugzilla ticket already exist to request this alert not occur during upgrades?
- If OCP should not be producing this alert, then it is valid to add the alert to the list of silenced alerts. SRE should also raise a BZ with the relevant OCP team to address this long-term.

An example of a non-actionable alert occuring during upgrades, which has had a Bugzilla raised to address it, is https://bugzilla.redhat.com/show_bug.cgi?id=1843595. Because there is a BZ raised, this alert is being silenced by the upgrade operator until resolution of the bug.

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
 * Reach out to **CCX** team via the ccx slack channel (@ccx in slack channel #ccx (CoreOS Workspace),clearly mentioning the requirements.
 * The **CCX** team will accordingly guide about accessing the data depending on the team's status and procedure of providing data access to a non-member of CCX team at that time.
 * The data provided by **CCX** (mostly the Jupyter notebook) will help in analysis of potential and suitable window timings for the upgrade timeout.
 * Once the timing has been finalised, upgrade the same on https://github.com/openshift/managed-cluster-config/blob/master/deploy/managed-upgrade-operator-config/10-managed-upgrade-operator-configmap.yaml
 * After successful upgradation and verification in staging environment, follow the steps on https://github.com/openshift/ops-sop/blob/master/v4/howto/push_operators_to_production.md to finally push the change to production environment.
