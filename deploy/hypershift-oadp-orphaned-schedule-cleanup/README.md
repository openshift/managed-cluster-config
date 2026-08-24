# OADP Orphaned Schedule Cleanup CronJob

Kubernetes CronJob to clean up orphaned Velero `Schedule` resources and their associated `FailedValidation` `Backup` resources on HyperShift Management Clusters.

## Background

This job implements the safe-cleanup recommendations from the `OADPBackupCRAccumulation` alert investigation runbook:

- [OADPBackupCRAccumulation SOP](https://github.com/openshift/ops-sop/blob/master/hypershift/alerts/oadp/OADPBackupCRAccumulation.md)

The alert fires when more than 100 Velero `Backup` CRs sit in a non-terminal phase (`Failed`, `PartiallyFailed`, `FailedValidation`, `Finalizing`, `Deleting`) for over an hour in the `openshift-adp` namespace on an HCP management cluster. A common root cause is a per-HostedCluster backup `Schedule` that still references a `BackupStorageLocation` (BSL) which no longer exists (`BSLNotFound`) — typically because the HostedCluster itself has since been deleted and its BSL/Schedule were never cleaned up.

## What This CronJob Does

The job evaluates every candidate Schedule (existing Schedules, plus any Schedule name still referenced by a `FailedValidation` Backup's `velero.io/schedule-name` label even if the Schedule object itself is gone) against this decision matrix:

| BSL exists? | Schedule exists? | Schedule has ownerReferences? | Action |
|---|---|---|---|
| Yes | — | — | **Skip** — not the BSLNotFound scenario; flag for manual review |
| No | No | — (backups unlabeled) | **Skip** — cannot safely target with a phase-aware, exact-name delete |
| No | No | — (backups labeled) | **Delete** the orphaned `FailedValidation` Backups only (no Schedule object to remove) |
| No | Yes | Yes | **Skip** — flag for manual investigation, never delete owned Schedules |
| No | Yes | No | **Delete** both the Schedule and its `FailedValidation` Backups |

Additional safety rules enforced by the script:

- **Static schedules are ignored**: any Schedule name matching `*-full-backup` (e.g. `daily-full-backup`, `weekly-full-backup`) is permanent, cluster-agnostic infrastructure, not a per-HostedCluster orphan candidate. These are quietly skipped up front and are **not** counted as needing manual review.
- **Cluster ID parsing**: the `CLUSTER_ID` used to check for a live HostedCluster is parsed directly from the Schedule name (convention: `<cluster-id>-hourly`, where the cluster ID is a 26-32 character lowercase alphanumeric string). If a name doesn't confidently match this pattern (and isn't a static schedule per above), the job **skips it and reports it for manual review** rather than guessing.
- **Exact-name deletes only**: Backup deletions always target explicit Backup CR names, never a bare `-l velero.io/schedule-name=<name>` label selector — that selector is not phase-aware and could otherwise catch backups in other non-terminal phases (e.g. `PartiallyFailed`) that must not be touched.
- **Unlabeled backups are never deleted**: `FailedValidation` Backups with no `velero.io/schedule-name` label are always skipped and reported only.

### Checks performed per candidate Schedule name

| Step | Description |
|------|-------------|
| 1 | If the name matches `*-full-backup`, skip quietly (static schedule, not an orphan candidate) |
| 2 | Parse `CLUSTER_ID` from the Schedule name; skip + report if unparseable |
| 3 | `oc get hc -A -l "api.openshift.com/id=${CLUSTER_ID}"` — skip if the HostedCluster still exists |
| 4 | `oc get backupstoragelocation ${SCHEDULE_NAME} -n openshift-adp` — skip if the BSL still exists; if the lookup fails for any reason other than a confirmed `NotFound`, skip and flag for manual review rather than assuming the BSL is absent |
| 5 | If the Schedule object still exists, check `ownerReferences` — skip + flag if owned |
| 6 | Delete the Schedule (if present); if that delete fails, skip Backup deletion for this candidate this run (retry next run) rather than deleting Backups out from under a Schedule that failed to delete |
| 7 | Delete each matching `FailedValidation` Backup by exact name |

### Summary

The CronJob outputs a per-item log line (`OK`/`FAIL`/`SKIP`) plus a final summary with counts for each outcome category and grand totals. Per-item lines are intentionally generic — they never include Schedule/Backup names, cluster IDs, or raw `oc` error output (see [No resource names or cluster IDs in logs](#safety) below).

## Deployment

This CronJob is deployed via SelectorSyncSet to all non-FedRAMP Management Clusters (`ext-hypershift.openshift.io/cluster-type: management-cluster`, excluding clusters labeled `api.openshift.com/fedramp: "true"`).

### Promotion Path

1. **Integration** — Test on int MCs first
2. **Stage** — Validate on staging MCs
3. **Production** — Roll out to all prod MCs

### Files

| File | Purpose |
|------|---------|
| `01-serviceaccount.yaml` | ServiceAccount for the CronJob (in `openshift-adp` namespace) |
| `02-clusterrole.yaml` | Cluster-scoped RBAC: HostedCluster get/list only (HostedClusters live outside `openshift-adp`) |
| `02-role.yaml` | Namespaced RBAC (in `openshift-adp`): Schedule get/list/delete, Backup get/list/delete, BackupStorageLocation get/list |
| `03-clusterrolebinding.yaml` | Binds the ClusterRole to the ServiceAccount |
| `03-rolebinding.yaml` | Binds the namespaced Role to the ServiceAccount (in `openshift-adp`) |
| `10-cronjob.yaml` | The cleanup CronJob (active by default, daily schedule, uses jq) |
| `config.yaml` | SelectorSyncSet targeting MCs only |

## Usage

Unlike some other OADP cleanup jobs in this repo, this CronJob is deployed **active** (`suspend: false`) on a daily schedule (`0 3 * * *` UTC), since it only ever deletes resources that are already confirmed orphaned by both the HostedCluster-existence and BSL-existence checks.

### Manual trigger

Create a Job from the CronJob template — can be run at any time, independent of the schedule:

```bash
oc create job --from=cronjob/oadp-orphaned-schedule-cleanup manual-cleanup-$(date +%s) \
  -n openshift-adp

# Watch progress
oc logs -n openshift-adp -f job/manual-cleanup-<timestamp>
```

### Pausing the schedule

```bash
oc patch cronjob oadp-orphaned-schedule-cleanup -n openshift-adp \
  --type merge -p '{"spec":{"suspend":true}}'
```

### Resuming the schedule

```bash
oc patch cronjob oadp-orphaned-schedule-cleanup -n openshift-adp \
  --type merge -p '{"spec":{"suspend":false}}'
```

## Monitoring

```bash
# List CronJob and spawned Jobs
oc get cronjob,jobs -n openshift-adp

# View logs from the most recent Job (selects the newest Job
# explicitly - a bare `-l job-name` selector matches Pods from
# every Job ever created by this CronJob, not just the latest)
JOB=$(oc get jobs -n openshift-adp \
  --sort-by=.metadata.creationTimestamp -o name | tail -1)
oc logs -n openshift-adp "$JOB" --tail=200

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
oc get jobs -n openshift-adp | grep orphaned-schedule-cleanup

# 2. Kill hung job (if needed)
oc delete job <job-name> -n openshift-adp

# 3. Trigger new run
oc create job --from=cronjob/oadp-orphaned-schedule-cleanup manual-cleanup-$(date +%s) -n openshift-adp
```

## Safety

- **Scoped**: only evaluates Velero `Schedule` and `FailedValidation` `Backup` resources in `openshift-adp`.
- **Least-privilege RBAC**: Velero `Schedule`/`Backup`/`BackupStorageLocation` permissions are granted via a namespaced `Role`/`RoleBinding` scoped to `openshift-adp` only. The `ClusterRole`/`ClusterRoleBinding` grants nothing more than read-only `get`/`list` on `HostedCluster` (cluster-scoped, since HostedClusters live outside `openshift-adp`).
- **Exact-name deletes**: Backups are always deleted by explicit name, never by a phase-unaware label selector.
- **Static schedules are ignored**: names matching `*-full-backup` are quietly skipped up front and never flagged for manual review.
- **Conservative cluster-ID parsing**: remaining schedules with a name that doesn't confidently match the expected `<cluster-id>-hourly` convention (26-32 character lowercase alphanumeric cluster ID) are skipped and reported rather than guessed at.
- **Two independent existence checks required**: both the HostedCluster and the BackupStorageLocation must be confirmed absent before anything is deleted.
- **Fail-closed inventory checks**: if the initial `oc get schedules`/`oc get backups` listing fails, the job aborts immediately instead of silently treating the failure as an empty inventory (which could otherwise misidentify owned Schedules or their Backups as orphaned).
- **Fail-closed BSL check**: a BSL is only treated as absent on a confirmed `NotFound`; any other lookup error causes the candidate to be skipped and flagged rather than assumed absent.
- **Schedule/Backup delete ordering**: Backups are only deleted after their Schedule has been successfully deleted (or was already absent). If a Schedule delete fails, its Backups are left alone that run and retried on the next scheduled run.
- **Owned Schedules are never deleted**: Schedules with `ownerReferences` are always flagged for manual investigation instead.
- **Unlabeled backups are never deleted**: reported for manual review only.
- **No resource names or cluster IDs in logs**: per-item log lines emit only generic status classifications (e.g. `SKIP: BackupStorageLocation still exists`) and the final summary reports aggregate counts only. Schedule/Backup names, parsed cluster IDs, and raw `oc` lookup error output are never printed, so retained Job logs cannot leak internal identifiers or API error details. To investigate a specific skip/failure, query the live cluster directly (e.g. `oc get schedules,backups -n openshift-adp -o wide`).
- **Idempotent**: safe to re-run; already-cleaned resources simply won't appear as candidates.
- **Concurrency protection**: `concurrencyPolicy: Forbid` prevents overlapping runs.
- **Resource limits**: the container defines both `requests` and `limits` (`memory: 512Mi`, `cpu: 500m`) to bound memory usage given the potentially large in-memory Schedule/Backup JSON inventories.
- **Read-only root filesystem**: the container runs with `readOnlyRootFilesystem: true`; a writable `emptyDir` is mounted at `/tmp` (with `HOME`/`TMPDIR` pointed there) for any temporary files `oc`/`jq` need to write.
- **History preserved**: previous Job logs can be reviewed via `oc get jobs` / `oc logs`.
- **Fails visibly on partial cleanup**: if any Schedule or Backup deletion fails, the job exits non-zero and the Job is marked failed (visible via `oc get jobs`) rather than silently reporting success.

## Related

- SOP: [OADPBackupCRAccumulation](https://github.com/openshift/ops-sop/blob/master/hypershift/alerts/oadp/OADPBackupCRAccumulation.md)
