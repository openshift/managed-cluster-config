# osd-cluster-ready RBAC

This directory contains the RBAC artifacts -- ServiceAccount and [Cluster]Role[Bindings] -- for the [osd-cluster-ready](https://github.com/openshift/osd-cluster-ready) Job that is managed by [configure-alertmanager-operator](https://github.com/openshift/configure-alertmanager-operator).

This is in lieu of having it either:
- In osd-cluster-ready itself.
  We have a [deploy/ directory](https://github.com/openshift/osd-cluster-ready/tree/master/deploy) there already, but those artifacts are not used for real deployments currently.
  Unclear how we would do that.
- In [configure-alertmanager-operator](https://github.com/openshift/configure-alertmanager-operator), because that would seem weird.

That said, it is awkward having it here, because now there are three different repositories that manage (different aspects of) osd-cluster-ready.
So we may some day try to move it.