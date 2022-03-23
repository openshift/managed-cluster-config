# ocm-agent-operator PrometheusRule

This will create a PrometheusRule for OAO in the staging and integration clusters to match the firing alerts as per [OSD-10251](https://issues.redhat.com/browse/OSD-10251).
OAO watches this PrometheusRule having send_managed_notification=true label and having a ManagedNotifications association label.

Contact Team Hulk for any more information.
`@ocm-agent-operator` or `#sd-sre-hulk slack` channel.
