# ocm-agent-operator PrometheusRule

This location manages `PrometheusRule` alerts that are intended to be routed to the cluster's OCM Agent, for the purpose of sending Service Logs to customers.


## How to make changes

Refer to the [OCM Agent SOP page](https://github.com/openshift/ops-sop/tree/master/v4/knowledge_base/ocm-agent.md) for the workflow of making changes to this resource.

It is important that every alert defined here contains a
- `send_managed_notification=true` label
- `managed_notification_template` label that maps to a template defined in the [`ManagedNotification` CR](../../ocm-agent-operator-managednotifications/10-managednotifications-cr.yaml)

## Links

- [OCM Agent Operator codebase](https://github.com/openshift/ocm-agent-operator)
- [OCM Agent codebase](https://github.com/openshift/ocm-agent)
- [OCM Agent Operator documentation drive](https://drive.google.com/drive/folders/1TsWeNHGDvyZJTtnmipFPrf8lx3SMhaat?usp=sharing)

## Contact

Contact Team Hulk for any more information.
`@ocm-agent-operator` or `#sd-sre-team-hulk` Slack channel.
