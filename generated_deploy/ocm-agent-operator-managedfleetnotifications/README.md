# ocm-agent-operator ManagedFleetNotifications-CR

This location manages the distribution of the OCM Agent Operator `ManagedFleetNotification` CR to hypershift-only OCM agent running on `rhobsp02ue1`.

The purpose of the `ManagedFleetNotification` CR is to define Service Log templates that map to AlertManager alerts, allowing the OCM Agent to build and send Service Logs when it is notified about those alerts.

The different to the `ManagedNotification` is that the Fleet alerts are working for hypershift.

## How to make changes

Refer to the [onboard OCM Agent SOP page](https://github.com/openshift/ops-sop/blob/master/v4/howto/onboard-an-ocmagent-alert.md#about-the-managedfleetnotification-custom-resource) for the workflow of making changes to this resource.

## Links

- [OCM Agent Operator codebase](https://github.com/openshift/ocm-agent-operator)
- [OCM Agent codebase](https://github.com/openshift/ocm-agent)
- [OCM Agent Operator documentation drive](https://drive.google.com/drive/folders/1TsWeNHGDvyZJTtnmipFPrf8lx3SMhaat?usp=sharing)

## Contact

Contact Team Hulk for any more information.
`@ocm-agent-operator` or `#sd-sre-team-hulk` Slack channel.
