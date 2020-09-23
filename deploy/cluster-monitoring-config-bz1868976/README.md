# Why?

Until https://bugzilla.redhat.com/show_bug.cgi?id=1868976 is fixed we need to turn of persistence for prometheus on clusters that hit the issue.

Because of https://issues.redhat.com/browse/CO-1188 going to toggle the label on and off.
And finally because of SDA bug that doesn't allow delete of a label with `/` we don't use `/`. (this is fixed but not renaming the key for this situation)

# How to turn this on?

```bash
CLUSTER_ID=1234asdf

cat << EOF | ocm post /api/clusters_mgmt/v1/clusters/$CLUSTER_ID/external_configuration/labels
{
    "key": "ext-managed.openshift.io-cluster-monitoring-config-bz1868976",
    "value": "true"
}
EOF


sleep 1

for LABEL_HREF in $(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID/external_configuration/labels | jq -r '.items[]? | select(.key == "ext-managed.openshift.io-cluster-monitoring-config-bz1868976") | .href');
do
    ocm delete $LABEL_HREF
done

sleep 1

cat << EOF | ocm post /api/clusters_mgmt/v1/clusters/$CLUSTER_ID/external_configuration/labels
{
    "key": "ext-managed.openshift.io-cluster-monitoring-config-bz1868976",
    "value": "true"
}
EOF
```

# How to turn this off (FOR ALL CLUSTERS)?

When we can turn this off simply delete the label and then we can delete this in MCC.

```bash
for CLUSTER_ID in $(ocm list clusters --managed --columns id | grep -v ^ID);
do
    for LABEL_HREF in $(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID/external_configuration/labels | jq -r '.items[]? | select(.key == "ext-managed.openshift.io-cluster-monitoring-config-bz1868976") | .href');
    do
        ocm delete $LABEL_HREF
    done
done
```
