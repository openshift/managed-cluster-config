This is temporary used to deploy the managedNotifcations CR and custom PrometheusRules to SREP owned production clusters (aka. osd-v4stg* and osd-v4prod* clusters).

Once they were verified that are working well there, will be managed by the following file for all the production deployment.

### 100-ocm-agent.PrometheusRule.yaml
`../sre-prometheus/ocm-agent/100-ocm-agent.PrometheusRule.yaml`

### 200-ocm-agent.managedNotifications.yaml
`../ocm-agent-operator-managednotifications/10-managednotifications-cr.yaml`