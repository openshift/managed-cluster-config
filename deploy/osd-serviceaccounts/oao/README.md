Whilst the openshift-ocm-agent-operator is in development, this location shall house MCC configuration intended only for staging and integration clusters.

Once the operator is ready for Production release, the changes listed below will be migrated to their more universal location.

### 00-ocm-agent-operator.ServiceAccount.yaml

Migrate to `../00-serviceaccounts.yaml`
