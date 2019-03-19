# hack

## Deploy Monitoring Customizations

### Deploy prometheus rules
`oc create -f deploy/prometheus/ -n openshift-monitoring`

### Deploy custom exporters

1. clone repo && cd to checkout

        git clone https://github.com/openshift/managed-prometheus-exporter-dns
        git clone https://github.com/openshift/managed-prometheus-exporter-stuck-ebs-vols
        git clone https://github.com/openshift/managed-prometheus-exporter-ebs-iops-reporter
1. `make`
1. `oc apply -f deploy`
