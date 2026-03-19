# OADP VSC Cleanup CronJob

Kubernetes CronJob to clean up orphan VolumeSnapshotContent (VSC), VolumeSnapshot (VS), DeleteBackupRequest (DBR), and Backup resources on HyperShift Management Clusters.

## Background

[SLSRE-531](https://redhat.atlassian.net/browse/SLSRE-531): Two categories of orphan resources accumulate on Management Clusters and need periodic cleanup:

- **Retain VSCs** (Part A): Legacy VSCs with `deletionPolicy: Retain` — caused by an incorrect VolumeSnapshotClass ([SLSRE-384](https://redhat.atlassian.net/browse/SLSRE-384)) — were never cleaned up after their parent Backup CRs expired (TTL).
- **Hourly-full-backup resources** (Part B): Old `hourly-full-backup-*` DBRs, Backups, VS, and VSCs from the deprecated MC full-backup schedule.

These cause:
- CSI driver performance degradation (6-9x slower snapshot operations)
- OADP backup queue accumulation (violating 6h RPO)
- Unnecessary AWS EBS snapshot costs

## What This CronJob Does

### Part A: Retain VSC Cleanup

| Step | Description |
|------|-------------|
| A1 | Gather all Velero-labelled VSCs with `deletionPolicy: Retain` |
| A2a | **Direct delete** — Retain VSCs without a bound VolumeSnapshot: patch to `Delete` policy, then delete VSC. Finalizers are patched after delete to unblock stuck-in-terminating VSCs. |
| A2b | **Cascade delete** — Retain VSCs with a bound VolumeSnapshot: patch to `Delete` policy, then delete VS (CSI cascade deletes VSC + EBS). |
| A3 | **Safeguard** — Re-scan for remaining Retain VSCs + bound VS. Deletes VS first (with finalizer patching), then VSC (with finalizer patching). Catches slow cascades. |

### Part B: Hourly-Full-Backup Cleanup

| Step | Description |
|------|-------------|
| B1 | Delete stuck `hourly-full-backup-*` DeleteBackupRequests |
| B2 | Delete `hourly-full-backup-*` Backups |
| B3a | **Direct delete** — Hourly VSCs without a bound VS: delete VSC, then patch finalizers to unblock terminating resources. |
| B3b | **Cascade delete** — Hourly VSCs with a bound VS: delete VS (cascade to VSC). Patches VS finalizers on failure. |
| B3c | **Orphaned VS** — Delete remaining `hourly-full-backup-*` VS by label (orphaned, not bound to any VSC). Patches finalizers on failure. |
| B4 | **Safeguard** — Re-scan for remaining hourly VSCs and delete with finalizer patching. |
| B4b | **Safeguard VS** — Re-scan for remaining hourly VS and delete with finalizer patching. |

### Summary

The CronJob outputs a combined summary with counts for each step (OK/FAIL) and grand totals.

## Deployment

This CronJob is deployed via SelectorSyncSet to all Management Clusters (`ext-hypershift.openshift.io/cluster-type: management-cluster`).

### Promotion Path

1. **Integration** — Test on int MCs first
2. **Stage** — Validate on staging MCs
3. **Production** — Roll out to all prod MCs

### Files

| File | Purpose |
|------|---------|
| `01-serviceaccount.yaml` | ServiceAccount for the CronJob (in `openshift-adp` namespace) |
| `02-clusterrole.yaml` | RBAC: VSC/VS get/list/patch/delete, Backup/DBR get/list/delete |
| `03-clusterrolebinding.yaml` | Binds ClusterRole to ServiceAccount |
| `10-cronjob.yaml` | The cleanup CronJob (suspended by default, uses jq) |
| `config.yaml` | SelectorSyncSet targeting MCs only |
| `audit-oadp-all-mcs.sh` | Unified read-only audit script (see [Audit Script](#audit-script)) |
| `trigger-cleanup-all-mcs.sh` | Multi-MC trigger / status / tail script (see [Trigger Script](#trigger-script)) |

## Usage

The CronJob deploys in a **suspended state** (`suspend: true`). This allows controlled, on-demand execution.

### Option 1: Manual trigger (recommended)

Create a Job from the CronJob template — can be run multiple times:

```bash
oc create job --from=cronjob/oadp-vsc-cleanup manual-cleanup-$(date +%s) \
  -n openshift-adp

# Watch progress
oc logs -n openshift-adp -f job/manual-cleanup-<timestamp>
```

### Option 2: Enable scheduled execution

Set a real cron schedule for periodic cleanup:

```bash
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

## Trigger Script

The `trigger-cleanup-all-mcs.sh` script automates triggering, checking status, and tailing logs across multiple MCs.

### Modes

| Mode | Description |
|------|-------------|
| `--trigger` | Create a manual Job on each MC, wait, show first N log lines (default) |
| `--check` | Check if CronJob exists on each MC and show its suspended state |
| `--status` | Check status of all `manual-cleanup-*` jobs on each MC |
| `--tail` | Show last N lines of logs for each `manual-cleanup-*` job on each MC |

### Options

| Option | Description |
|--------|-------------|
| `--mc <name>` | Target only this MC (repeatable). Skips OCM discovery. |
| `--lines <N>` | Number of log lines to show (default: 50). Used in `--trigger` and `--tail`. |
| `--wait <seconds>` | Seconds to wait for pod logs after creation (default: 30). `--trigger` only. |
| `--dry-run` | Only show what would be done; do not create jobs. `--trigger` only. |

### Examples

```bash
# Trigger on all MCs (OCM autodiscovery)
./trigger-cleanup-all-mcs.sh --trigger

# Trigger on specific MCs
./trigger-cleanup-all-mcs.sh --trigger --mc hs-mc-aaa --mc hs-mc-bbb

# Trigger on all MCs with more wait and log lines
./trigger-cleanup-all-mcs.sh --trigger --lines 100 --wait 60

# Check which MCs have the CronJob deployed
./trigger-cleanup-all-mcs.sh --check

# Check job status across all MCs
./trigger-cleanup-all-mcs.sh --status

# Show last 100 lines of each job's logs
./trigger-cleanup-all-mcs.sh --tail --lines 100 --mc hs-mc-aaa

# Dry run (no jobs created)
./trigger-cleanup-all-mcs.sh --trigger --dry-run
```

## Audit Script

The `audit-oadp-all-mcs.sh` script provides a unified read-only audit across Management Clusters. It supports different cases matching the CronJob parts.

### Cases

| Case | CronJob Part | Columns |
|------|-------------|---------|
| `hourly` (default) | Part B | `HOURLY_DBR`, `HOURLY_BKP`, `HOURLY_VS`, `HOURLY_VSC`, VSC EBS status, stuck DBRs |
| `retain` | Part A | `TOTAL_VSC`, `VELERO_VSC`, `VELERO_VS`, `RETAIN_VSC`, `RETAIN_VS` |
| `all` | Both | Combined key columns from both cases |

### Options

| Option | Description |
|--------|-------------|
| `--case <hourly\|retain\|all>` | Audit case (default: `hourly`) |
| `--mc <name>` | Audit only this MC (repeatable). Skips OCM discovery. |
| `--check-aws` | Enable AWS EBS snapshot counting (needs creds, slower). Adds `EBS_SNAPS` column. |
| `--detail` | Per-VSC detail table (`hourly`/`all` cases only). |
| `-o <file>` | Write TSV summary to file (for before/after diff). |
| `-n <namespace>` | Namespace for DBR/Backup (default: `openshift-adp`). |

### Prerequisites

```bash
# 1. OCM login
ocm login --token=... --url=integration   # integration
ocm login --token=... --url=staging        # stage
ocm login --token=... --url=production     # production

# 2. For --check-aws (Kerberos + SAML):
kinit $USER@IPA.REDHAT.COM

# Integration / Stage:
rh-aws-saml-login osd-staging-1

# Production:
rh-aws-saml-login rh-control
```

### Examples

```bash
# Hourly audit (default), all MCs
./audit-oadp-all-mcs.sh

# Retain audit with AWS EBS count
./audit-oadp-all-mcs.sh --case retain --check-aws

# Combined overview, single MC
./audit-oadp-all-mcs.sh --case all --mc hs-mc-xxx

# Hourly with per-VSC detail + AWS cross-check
./audit-oadp-all-mcs.sh --case hourly --detail --check-aws --mc hs-mc-xxx

# Before/after diff
./audit-oadp-all-mcs.sh -o before.tsv
# ... run cleanup ...
./audit-oadp-all-mcs.sh -o after.tsv
diff before.tsv after.tsv
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
- `successfulJobsHistoryLimit: 3` — Keeps last 3 successful Jobs
- `failedJobsHistoryLimit: 3` — Keeps last 3 failed Jobs
- `ttlSecondsAfterFinished: 604800` — Auto-deletes Jobs after 7 days

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
- 1,000 orphan resources: ~5 minutes
- 5,000 orphan resources: ~20 minutes
- 15,000 orphan resources: ~50 minutes

## Safety

- **Scoped**: Part A targets only Retain VSCs. Part B targets only `hourly-full-backup-*` resources (DBR, Backup, VS, VSC). Does not touch `<cluster-id>-6-hourly-*` HC backups.
- **Finalizer handling**: Patches out stuck finalizers after delete to unblock terminating resources.
- **No AWS credentials needed**: CSI driver handles EBS cleanup in the normal path.
- **Idempotent**: Safe to re-run; skips already-processed resources.
- **Concurrency protection**: `concurrencyPolicy: Forbid` prevents overlapping runs.
- **Throttled**: 0.2s pause between deletions to prevent CSI/AWS API overload.
- **History preserved**: Can review previous Job logs.

## Related

- JIRA: [SLSRE-531](https://redhat.atlassian.net/browse/SLSRE-531)
