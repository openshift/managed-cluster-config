# hack

## Monitoring Customizations

### Deploy prometheus rules

`oc create -f deploy/prometheus/ -n openshift-monitoring`

### Deploy custom exporters

`oc create -f deploy/exporter-dns/ -n openshift-monitoring`
`oc create -f deploy/exporter-ebs-iops-reporter/ -n openshift-monitoring`
`oc create -f deploy/exporter-stuck-ebs-vols/ -n openshift-monitoring`

## Dedicated admin

`oc create -f deploy/dedicated-admin`
