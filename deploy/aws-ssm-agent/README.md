# ROSA HCP Management Clusters and AWS SSM Agent

Kubelet debugging handlers are disabled on ROSA HCP management clusters via the [enableDebuggingHandlers](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/#kubelet-config-k8s-io-v1beta1-KubeletConfiguration) flag. Among other things, this means that we lose the ability to exec into containers, causing `oc debug` to not function.

[AWS SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html) is software that will allow SREs to connect to EC2 instances underlying the management cluster directly to replace workflows requiring `oc debug`.

## References

* [OSD-19613](https://issues.redhat.com/browse/OSD-19613)
* [OSD-19654](https://issues.redhat.com/browse/OSD-19654)
