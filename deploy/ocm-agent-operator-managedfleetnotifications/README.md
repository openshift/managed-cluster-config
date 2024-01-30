# ocm-agent-operator ManagedFleetNotifications-CR

This location manages the distribution of the OCM Agent Operator `ManagedFleetNotification` CR to hypershift-only OCM agent running on `rhobsp02ue1`.

The purpose of the `ManagedFleetNotification` CR is to define notification templates that map to AlertManager alerts, allowing the OCM Agent to build and send notifications when it is notified about those alerts.

`ManagedNotifications` are specifically for HyperShift and are currently sent from a centralized place (`rhobsp02ue1`) to the whole fleet of HCP clusters. Furthermore, `ManagedNotifications` support notifications of type limited support by setting the `limitedSupport` field to `true`. 

## How to make changes

Refer to the [onboard OCM Agent SOP page](https://github.com/openshift/ops-sop/blob/master/v4/howto/onboard-an-ocmagent-alert.md#about-the-managedfleetnotification-custom-resource) for the workflow of making changes to this resource.

## Links

- [OCM Agent Operator codebase](https://github.com/openshift/ocm-agent-operator)
- [OCM Agent codebase](https://github.com/openshift/ocm-agent)
- [OCM Agent Operator documentation drive](https://drive.google.com/drive/folders/1TsWeNHGDvyZJTtnmipFPrf8lx3SMhaat?usp=sharing)

## Contact

Contact Team Hulk for any more information.
`@ocm-agent-operator` or `#sd-sre-team-hulk` Slack channel.
