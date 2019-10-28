# Namespaces where PV quotas do not apply, space separated.
PERSISTENT_VOLUME_EXCEPTIONS ?= openshift-etcd openshift-monitoring

# Namespaces where load balancer quotas do not apply, space separated.
LOAD_BALANCER_EXCEPTIONS ?= openshift-ingress

# Default PV quota per namespace in Gi
DEFAULT_PV_QUOTA ?= 100Gi

# Default Load balancer per namespace quota
DEFAULT_LB_QUOTA ?= 0

# What label to be set when the LoadBalancer and/or Persistent Volume quotas do
# not apply
LB_EXCLUSION_LABEL_NAME ?= managed.openshift.io/service-lb-quota-exempt
PV_EXCLUSION_LABEL_NAME ?= managed.openshift.io/storage-pv-quota-exempt
