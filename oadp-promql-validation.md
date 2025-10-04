# OADP Validation - PromQL Queries

## Core Status Queries (Following MVO Pattern)

### Total Clusters with OADP Installed
```promql
count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))
```

### Total Clusters with MVO Installed (Baseline)
```promql
count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}))
```

### OADP Migration Progress
```promql
# Percentage of MVO clusters that now have OADP
(count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) / count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}))) * 100
```

### Clusters with Both MVO and OADP (Migration Phase)
```promql
count(
  (count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"})) and
  (count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))
)
```

### Clusters with OADP Only (Migration Complete)
```promql
count(
  (count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) and on(_id)
  (count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}) == 0)
)
```

### OADP Operator Health
```promql
# Successful OADP operators
count(csv_succeeded{name=~"oadp-operator.*"} == 1)

# Failed OADP operators
count(csv_succeeded{name=~"oadp-operator.*"} == 0)

# OADP operator success rate
(count(csv_succeeded{name=~"oadp-operator.*"} == 1) / count(csv_succeeded{name=~"oadp-operator.*"})) * 100
```

### Hive Target Validation
```promql
# Clusters targeted by OADP SelectorSyncSet
count(count by (_id) (selectorsyncset_applied_total{name="velero-configuration-hive-specific"}))

# OADP deployment success rate on target clusters
(count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) / count(count by (_id) (selectorsyncset_applied_total{name="velero-configuration-hive-specific"}))) * 100
```

## Key Monitoring Queries

### OADP vs MVO Status Summary
```promql
# MVO only (not migrated yet)
count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"})) - count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))

# Both systems (migration in progress)
count(
  (count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"})) and
  (count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))
)

# OADP only (migration complete)
count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) - count(
  (count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"})) and
  (count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))
)
```

## Dashboard Panels

### Panel 1: Migration Progress (Stat)
```promql
(count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) / count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}))) * 100
```

### Panel 2: OADP Health (Stat)
```promql
(count(csv_succeeded{name=~"oadp-operator.*"} == 1) / count(csv_succeeded{name=~"oadp-operator.*"})) * 100
```

### Panel 3: Total Deployments (Stat)
```promql
count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))
```

## Alert Rules

### Critical Alerts
```promql
# OADP operator installation failure
csv_succeeded{name=~"oadp-operator.*"} == 0

# Migration stalled (no progress in 24h)
increase(count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))[24h]) == 0
```

### Warning Alerts
```promql
# Low OADP deployment coverage (<90%)
(count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) / count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}))) * 100 < 90

# SelectorSyncSet application failures
increase(selectorsyncset_resource_apply_failure_total{name="velero-configuration-hive-specific"}[5m]) > 0
```

## Quick Team Status Check

### Single Health Score Query
```promql
# Overall OADP migration health (0-100%)
(
  # Deployment coverage (50% weight)
  ((count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) / count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}))) * 50) +
  # Operator success rate (50% weight)
  ((count(csv_succeeded{name=~"oadp-operator.*"} == 1) / count(csv_succeeded{name=~"oadp-operator.*"})) * 50)
)
```

## Comparison Queries (OADP vs MVO)

### Before Migration (MVO Baseline)
```promql
count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}))
```

### After Migration (OADP Target)
```promql
count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"}))
```

### Migration Delta
```promql
count(count by (_id) (csv_succeeded{name=~"oadp-operator.*"})) - count(count by (_id) (csv_succeeded{name=~"managed-velero-operator.*"}))
```