# Managed Cluster PrometheusRules

This section contains alerts specifically crafted for managed OpenShift clusters.

Alerts and recording rules have been evaluated not the be suitable to be contibuted to the
[kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin) or to any OCP component.

## Contributing
For contributions here, please make sure to follow the template.
It will ask you to make sure that you evaluated that those rules cannot be contributed back to the community
and are specific to managed OpenShift.

| Criteria                    | Yes/No |
|-----------------------------|--------|
| works on vanilla Kubernetes |        |
| works on vanilla OCP        |        |
| works on managed OpenShift  |        |


## Workflow
* Create and Issue or a Jira ticket that explains your change and the reason
* fork this repository
* evaluate your alerts with the given matrix above
* create a PR for your change, following the template
* wait for a review
