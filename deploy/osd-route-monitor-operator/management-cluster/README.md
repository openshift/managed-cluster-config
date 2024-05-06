This subfolder is a workaround for https://issues.redhat.com/browse/OSD-20289 / https://issues.redhat.com/browse/OCPBUGS-30260. Once https://issues.redhat.com/browse/OSD-20289 is resolved, we should remove this folder and remove the following in the `config.yaml` under the parent `osd-route-monitor-operator` folder:
```
  - key: ext-hypershift.openshift.io/cluster-type
    operator: NotIn
    values: 
      - "management-cluster"
```

With this subfolder, we're essentially disabling the console-ErrorBudgetBurn alerts for all management clusters as they are constantly paging due to https://issues.redhat.com/browse/OCPBUGS-30260. 