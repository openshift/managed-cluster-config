# Pruning Resources on cluster

This folder is required to clean up stuff from the cluster that is left over for some reason

# How to build
## test manually
firstly, run the commands manually on the cluster to see what commands need to be run automatically

### extract RBAC rules required
after the script is done look at all of the commands and try to extract the rules you need,

For example the command:
```
oc delete job
```
this means you need to add the verb `delete` to the resource named `jobs`

And to figure out what the group is, you can look at the resource you are manipulating in the `.apiVersion` till the first '/'

So for our example:
```
NS=
JOBNAME=
oc get job ${JOBNAME} -n ${NS} -ojson | jq .apiVersion | cut -d/ -f1

batch
```
and if you are lucky you could find the resource name from a quick `grep -inIr '- jobs'` in this repo.

### create a CronJob
from the scripts you need to create a cronjob (template can be extracted from the present cronjobs) and paste the script there

## test on cluster
after creating all of the scripts you will need to verify it works well. You can `oc apply` the resources and to make testing faster you can also:

```
CRONJOB_NAME=
JOBNAME=
NS=
oc create job --from cj/${CRONJOB_NAME} -n ${NS} ${JOBNAME}
oc logs job/${JOBNAME} -f -n ${NS}
```

And then see if the job works as expected

## Best Practices for one time jobs

### Delete resources after creation
if you want the resource to self-clean, you need to allow a `oc delete cronjob ${CRONJOB_NAME} && oc delete job ${JOBNAME}`  at the end, that way you can delete the whole cronjob and the spawned jobs will self clean as well

### Use least privilege
when creating RBAC, it's worth the time and effort giving the minimal amount of permissions to your process, to keep the attack surface of your process low

### Make job idempotent
if there are no resources to delete, do not do any operation and fail fast
