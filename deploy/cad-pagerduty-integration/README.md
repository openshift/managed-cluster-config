# CAD PagerDuty Integration Key (Patch)

This patch adds the `CAD_PAGERDUTY_KEY` to the existing `pd-secret` in the `openshift-monitoring` namespace.

## References

- [configure-alertmanager-operator](https://github.com/openshift/configure-alertmanager-operator) reads the CAD key and configures alertmanager routing
