# Secret for configuring OBO Alertmanager

This location manages the distribution of the secret of OBO Alertmanager to the fleet of management clusters.

The purpose of the secret `alertmanager-hypershift-monitoring-stack` is to configure OBO Alertmanager to have a HTTP endpoint of ocm-agent-fleet as webhook receiver, allowing the OBO Alertmanager to emit alerts payload to ocm-agent-fleet and sending `ManagedFleetNotifications` to the customers.

## Secret configuration
- The manifest of the secret resource in OBO MonitoringStack
```
oc-admin get secret -n openshift-observability-operator alertmanager-hypershift-monitoring-stack -oyaml
apiVersion: v1
data:
  alertmanager.yaml: Z2xvYmFsOgogIHJlc29sdmVfdGltZW91dDogNW0Kcm91dGU6CiAgcmVjZWl2ZXI6ICJudWxsIgogIHJvdXRlczoKICAtIHJlY2VpdmVyOiBvY21hZ2VudAogICAgbWF0Y2hlcnM6CiAgICAtIHNlbmRfbWFuYWdlZF9ub3RpZmljYXRpb24gPSB0cnVlCiAgICByZXBlYXRfaW50ZXJ2YWw6IDEwbQogIC0gcmVjZWl2ZXI6ICJudWxsIgogIGdyb3VwX3dhaXQ6IDMwcwogIGdyb3VwX2ludGVydmFsOiA1bQogIHJlcGVhdF9pbnRlcnZhbDogMTJoCnJlY2VpdmVyczoKLSBuYW1lOiBvY21hZ2VudAogIHdlYmhvb2tfY29uZmlnczoKICAtIHNlbmRfcmVzb2x2ZWQ6IHRydWUKICAgIHVybDogaHR0cDovL29jbS1hZ2VudC1mbGVldC5vcGVuc2hpZnQtb2NtLWFnZW50LW9wZXJhdG9yLnN2Yy5jbHVzdGVyLmxvY2FsOjgwODEvYWxlcnRtYW5hZ2VyLXJlY2VpdmVyCi0gbmFtZTogIm51bGwiCg==
kind: Secret
metadata:
  name: alertmanager-hypershift-monitoring-stack
  namespace: openshift-observability-operator
type: Opaque
```
- The decoded base64 secret configuration in the data field 
```
global:
  resolve_timeout: 5m
route:
  receiver: "null"
  routes:
  - receiver: ocmagent
    matchers:
    - send_managed_notification = true
    repeat_interval: 10m
  - receiver: "null"
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
receivers:
- name: ocmagent
  webhook_configs:
  - send_resolved: true
    url: http://ocm-agent-fleet.openshift-ocm-agent-operator.svc.cluster.local:8081/alertmanager-receiver
- name: "null"
```

## Links

- [EPIC - Implement ocm-agent for Hypershift without RHOBS](https://issues.redhat.com/browse/SDE-3526)
- [Design Doc of the EPIC](https://docs.google.com/document/d/1eC5j1f-j-AAlPFgg4ck-zFGUP1pGNr-8cKTyvLYOYYg/edit#heading=h.bupciudrwmna)
- [OCM Agent codebase](https://github.com/openshift/ocm-agent)

## Contact

Contact Team Thor or Team Hulk for any more information.
`#sd-sre-team-thor` or `#sd-sre-team-hulk` Slack channel.
