# OADP VSC Cleanup CronJob

Kubernetes CronJob to clean up orphan VolumeSnapshotContent (VSC) resources on HyperShift Management Clusters.

## Background

SLSRE-531: Legacy VSCs with `deletionPolicy: Retain` were never cleaned up after their parent Backup CRs expired (TTL). This causes:
- CSI driver performance degradation (6-9x slower snapshot operations)
- OADP backup queue accumulation (violating 6h RPO)
- Unnecessary AWS EBS snapshot costs

## What This CronJob Does

1. Finds all VSCs with `velero.io/backup-name` label and `deletionPolicy: Retain`
2. Does *not* check whether the corresponding Backup CR still exists — removes all such Retain VSCs
3. For each Retain VSC:
   - If a VolumeSnapshot (VS) exists: patches VSC to `Delete`, then deletes the VS (cascade deletes VSC)
   - If no VS exists: patches VSC to `Delete` and deletes the VSC directly
4. **Final pass**: Re-scans for any remaining Retain VSCs (e.g. cascade from step 3 not yet completed) and deletes them directly.
5. CSI driver cleans up the underlying AWS EBS snapshot when the VSC is deleted

## Deployment

This CronJob is deployed via SelectorSyncSet to all Management Clusters (`ext-hypershift.openshift.io/cluster-type: management-cluster`).

### Promotion Path

1. **Integration** - Test on int MCs first
2. **Stage** - Validate on staging MCs
3. **Production** - Roll out to all 77 prod MCs

### Files

| File | Purpose |
|------|---------|
| `01-serviceaccount.yaml` | ServiceAccount for the CronJob (in `openshift-adp` namespace) |
| `02-clusterrole.yaml` | RBAC: VSC/VS get/list/patch/delete, Backup get/list |
| `03-clusterrolebinding.yaml` | Binds ClusterRole to ServiceAccount |
| `10-cronjob.yaml` | The cleanup CronJob (suspended by default, uses jq) |
| `config.yaml` | SelectorSyncSet targeting MCs only |
| `audit-vsc-ebs-all-mcs.sh` | Read-only audit: same K8s counts as cron + EBS snapshot count per MC (for before/after comparison) |

## Usage

The CronJob deploys in a **suspended state** (`suspend: true`). This allows controlled, on-demand execution.

### Option 1: Manual trigger (recommended)

Create a Job from the CronJob template - can be run multiple times:

```bash
# Create a Job from the CronJob (can run this anytime)
oc create job --from=cronjob/oadp-vsc-cleanup manual-cleanup-$(date +%s) \
  -n openshift-adp

# Watch progress
oc logs -n openshift-adp -f job/manual-cleanup-<timestamp>
```

### Option 2: Enable scheduled execution

Set a real cron schedule for periodic cleanup:

```bash
# Enable with weekly schedule (every Sunday 2am)
oc patch cronjob oadp-vsc-cleanup -n openshift-adp \
  --type merge -p '{"spec":{"schedule":"0 2 * * 0","suspend":false}}'
```

### Option 3: One-time via unsuspend

```bash
# Unsuspend to trigger immediately on next schedule tick
oc patch cronjob oadp-vsc-cleanup -n openshift-adp \
  --type merge -p '{"spec":{"suspend":false}}'

# Re-suspend after Job starts
oc patch cronjob oadp-vsc-cleanup -n openshift-adp \
  --type merge -p '{"spec":{"suspend":true}}'
```

## Monitoring

```bash
# List CronJob and spawned Jobs
oc get cronjob,jobs -n openshift-adp

# View logs from latest Job
oc logs -n openshift-adp -l job-name --tail=200

# View specific Job logs
oc logs -n openshift-adp job/<job-name>
```

## Job History

The CronJob keeps history of recent runs:
- `successfulJobsHistoryLimit: 3` - Keeps last 3 successful Jobs
- `failedJobsHistoryLimit: 3` - Keeps last 3 failed Jobs
- `ttlSecondsAfterFinished: 604800` - Auto-deletes Jobs after 7 days

## Troubleshooting

### Re-execute if job hangs

```bash
# 1. Check running jobs
oc get jobs -n openshift-adp | grep cleanup

# 2. Kill hung job (if needed)
oc delete job <job-name> -n openshift-adp

# 3. Trigger new run
oc create job --from=cronjob/oadp-vsc-cleanup manual-cleanup-$(date +%s) -n openshift-adp
```

### Estimated duration

The script has built-in throttling (0.2s sleep per deletion) to avoid overwhelming the CSI driver:
- 1,000 orphan VSCs: ~5 minutes
- 5,000 orphan VSCs: ~20 minutes
- 15,000 orphan VSCs: ~50 minutes

## Safety

- **Retain-only**: Only touches VSCs with `deletionPolicy: Retain` (and their VS if present). Does not check Backup CR existence.
- **No AWS credentials needed**: CSI driver handles AWS snapshot deletion
- **Idempotent**: Safe to re-run; skips already-processed VSCs
- **Concurrency protection**: `concurrencyPolicy: Forbid` prevents overlapping runs
- **Throttled**: 0.2s pause between deletions to prevent CSI/AWS API overload
- **History preserved**: Can review previous Job logs

## Before/after cleanup verification (many MCs)

Use the read-only audit script to compare state before and after running cleanup:

```bash
# Prerequisites (once): ocm login, kinit, rh-aws-saml-login osd-staging-1 (or rh-control)

# Before cleanup
./audit-vsc-ebs-all-mcs.sh -o audit_before.tsv

# Run cleanup (CronJob or manual job on each MC)
# ...

# After cleanup
./audit-vsc-ebs-all-mcs.sh -o audit_after.tsv

# Compare
diff audit_before.tsv audit_after.tsv
```

The script reports per MC: TOTAL_VSC, VELERO_VSC, RETAIN_VSC, VS count, EBS snapshot count (same logic as the cron). Use `--mc hs-mc-xxx` to audit specific MCs, or `--skip-aws` for K8s-only (faster).

## Related

- JIRA: [SLSRE-531](https://issues.redhat.com/browse/SLSRE-531)

