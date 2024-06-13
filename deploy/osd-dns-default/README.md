# OSD-22081

This will allow dns-default pods to run on every node of a cluster.

This did lead to problems, when infra nodes were using worker nodes that were
overloaded to handle the DNS requests.

Instead with this patch, the infra nodes will get their own dns-default pods,
removing this source of issues.

This patch has to patch-in the default master-toleration as well, as just adding
the infra toleration will remove the implicit master toleration that is present
in a default installation.
