# PrometheusRule unit tests

Every alert in `deploy/` must have a unit test. A unit test gives Prometheus example metric values and checks which alerts fire, and when. We run the tests with `promtool test rules` on every pull request in the `pr-check` job.

This document is for people and for AI agents. It explains where tests go, how to write them, how to run them, and what the CI check requires.

## Requirements

1. Every alerting rule in a `PrometheusRule` file under `deploy/` must have at least one test case where the alert fires.
2. Each `PrometheusRule` file has one test file. The test file is in `tests/prometheusrules/`, at a path that mirrors the rule file (see [Where test files go](#where-test-files-go)).
3. A test file lists exactly one rule file in `rule_files`, using the path from the repository root.
4. Alerts that existed before this check have an entry in `tests/prometheusrules/exceptions.yaml`. Do not add new alerts to that file.
5. If you change the `expr`, `for`, `keep_firing_for` or `labels` of an alert in `exceptions.yaml`, you must add a test for it and remove it from `exceptions.yaml`.

The check covers both `PrometheusRule` API groups we use: `monitoring.coreos.com/v1` (the platform monitoring stack) and `monitoring.rhobs/v1` (the Observability Operator).

## Where test files go

Take the path of the rule file, remove `deploy/`, put it under `tests/prometheusrules/`, and replace `.yaml` or `.yml` with `.test.yaml`.

| Rule file | Test file |
|---|---|
| `deploy/sre-prometheus/100-sre-kubequotaexceeded.PrometheusRule.yaml` | `tests/prometheusrules/sre-prometheus/100-sre-kubequotaexceeded.PrometheusRule.test.yaml` |
| `deploy/sre-prometheus/management-cluster/100-obo-stack-monitoring.PrometheusRule.yml` | `tests/prometheusrules/sre-prometheus/management-cluster/100-obo-stack-monitoring.PrometheusRule.test.yaml` |

Test files must not be in `deploy/`. Every YAML file in a `deploy/` directory becomes part of a SelectorSyncSet (`scripts/generate_template.py`), so a test file there would be deployed to clusters.

If you rename or delete a rule file, move or delete its test file in the same pull request. The check fails if a test file points to a rule file that does not exist.

## How a test works

`promtool` cannot read a `PrometheusRule` resource. It needs plain rule groups. `scripts/check_prometheusrule_tests.py` does this for you:

1. It reads `spec` from the rule file named in `rule_files`.
2. It writes `spec` to a temporary file.
3. It points the test at the temporary file and runs `promtool test rules`.

The rest of the test file uses the normal `promtool` format. The upstream reference is [Unit testing for rules](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/).

## Write a test

This is the complete test for `KubeQuotaExceededSRE`. The rule fires when a ResourceQuota in a platform namespace uses more than its hard limit for 30 minutes.

```yaml
rule_files:
  - deploy/sre-prometheus/100-sre-kubequotaexceeded.PrometheusRule.yaml

evaluation_interval: 1m

tests:
  - name: quota exceeded in a platform namespace for longer than 30m
    interval: 1m
    input_series:
      - series: 'kube_resourcequota{namespace="openshift-example",job="kube-state-metrics",resource="pods",resourcequota="example",type="used",instance="ksm:8443"}'
        values: '11x40'
      - series: 'kube_resourcequota{namespace="openshift-example",job="kube-state-metrics",resource="pods",resourcequota="example",type="hard",instance="ksm:8443"}'
        values: '10x40'
    alert_rule_test:
      # The condition is true, but "for: 30m" has not passed yet.
      - eval_time: 29m
        alertname: KubeQuotaExceededSRE
        exp_alerts: []
      - eval_time: 31m
        alertname: KubeQuotaExceededSRE
        exp_alerts:
          - exp_labels:
              severity: warning
              namespace: openshift-monitoring
              resource: pods
              resourcequota: example
            exp_annotations:
              message: Quota limit exceeded in namespace openshift-example.

  - name: quota exceeded in a customer namespace does not fire
    interval: 1m
    input_series:
      - series: 'kube_resourcequota{namespace="customer-app",job="kube-state-metrics",resource="pods",resourcequota="example",type="used",instance="ksm:8443"}'
        values: '11x40'
      - series: 'kube_resourcequota{namespace="customer-app",job="kube-state-metrics",resource="pods",resourcequota="example",type="hard",instance="ksm:8443"}'
        values: '10x40'
    alert_rule_test:
      - eval_time: 31m
        alertname: KubeQuotaExceededSRE
        exp_alerts: []
```

### Fields you will use

| Field | Meaning |
|---|---|
| `evaluation_interval` | How often `promtool` evaluates the rules. The default is `1m`. For tests that cover many hours, use `5m`, and put every `eval_time` at least one interval after the time you expect the alert to change. Rules with long subqueries (for example `[24h:5m]`) are slow at `1m`. |
| `group_eval_order` | The order in which rule groups are evaluated. List the recording rule group before the alert group. |
| `interval` | Time between samples in `input_series`. Use `5m` for tests that cover many hours, so the series stay short. |
| `input_series[].series` | A series name and its labels, in PromQL notation. |
| `input_series[].values` | Sample values. `11x40` means the value 11, then 40 more samples of 11. `0+1x30` means 0, 1, 2, ... 30. `_` is a missing sample. `stale` marks the series as gone. |
| `eval_time` | The time to check, counted from the first sample. |
| `alertname` | The alert to check. It must be defined in the rule file. |
| `exp_alerts` | Every alert with this name that fires at `eval_time`. An empty list means the alert must not fire. |
| `exp_labels` | The full label set of one alert, without `alertname`. |
| `exp_annotations` | The full annotation set of one alert, with templates expanded. |

### What a good test checks

Each alert should have at least these cases:

1. **Not firing yet.** The condition is true, but the `for` time has not passed. Use an `eval_time` just before the `for` time ends.
2. **Firing.** After the `for` time, the alert fires with the exact labels and annotations. The CI check needs at least one case like this for each alert.
3. **Filtered out.** Input that looks close but must not fire. For example, the same metric in a customer namespace, a value exactly at the threshold, or a counter that does not change.

Add more cases when the rule has branches, for example `or`, `unless`, or `absent()`.

### Things that are easy to get wrong

- `promtool` compares labels and annotations **exactly**. List every label and every annotation of the alert. If you leave out `exp_annotations`, `promtool` expects the alert to have no annotations.
- A label set in the rule replaces the label from the series. For example, `KubeQuotaExceededSRE` sets `namespace: openshift-monitoring`. Templates in annotations still see the original series labels, so the message uses `openshift-example`.
- A label can be a template, for example `namespace: '{{ $labels.namespace }}'`. In `exp_labels`, write the expanded value.
- One alert name can have more than one rule, for example a warning after 15 minutes and a critical after 24 hours. `exp_alerts` must list every alert with that name that fires at `eval_time`, and the CI check needs a firing case for each rule. See `100-control-plane-resizing.PrometheusRule.test.yaml`.
- `absent(metric{a="b"})` returns a series with the labels from the equality matchers (`a="b"`). Expect those labels on the alert. See `100-configure-alertmanager-operator.PrometheusRule.test.yaml`.
- Recording rules in the same file run during the test. Give the raw input series, not the recorded series. See `100-sre-kubejobfailing.PrometheusRule.test.yaml`.
- When the recording rules and the alerts are in different groups, set `group_eval_order` with the recording group first. `promtool` does not guarantee the order of groups that are not listed. Without it, the alert can see the recorded value one evaluation late, and the test can pass on one run and fail on the next.
- Some rules read recording rules from the OpenShift platform, for example `cluster:nodes_roles`. These are not in this repository. Give them as input series.
- `increase()` and `rate()` need at least two samples in the range. A counter that increases once is not the same as a counter that keeps increasing.

### Examples in this repository

| Test file | Shows |
|---|---|
| `100-sre-kubequotaexceeded.PrometheusRule.test.yaml` | Threshold with `for`, namespace filter, label that replaces a series label |
| `100-configure-alertmanager-operator.PrometheusRule.test.yaml` | `absent()`, and a series that goes `stale` |
| `100-haproxy-reload-fails.Prometheusrule.test.yaml` | Counter with `increase()` over a range |
| `100-sre-kubejobfailing.PrometheusRule.test.yaml` | Recording rules from the same file |
| `100-control-plane-resizing.PrometheusRule.test.yaml` | One alert name with two rules, platform recording rules as input, long time ranges |

All of them are in `tests/prometheusrules/sre-prometheus/`.

## Run the tests

From the repository root:

```bash
make test-prometheusrules
```

This builds the `Dockerfile.prow` image (the same image as the `pr-check` job) and runs, in the container:

1. The unit tests for the runner itself (`scripts/test_check_prometheusrule_tests.py`).
2. `scripts/check_prometheusrule_tests.py`, which runs every test file and the coverage check.

If you already have `python3` with `oyaml` and `promtool` 3.9.1 on your machine, you can run the script directly:

```bash
scripts/check_prometheusrule_tests.py
# Or with a promtool binary that is not on your PATH:
scripts/check_prometheusrule_tests.py --promtool /path/to/promtool
```

The `--skip-promtool` flag checks only the file layout and coverage. It is fast, but it does not run the tests.

## The coverage check and the exception list

### How it decides that an alert is tested

An alert is tested when a test file for its rule file has at least one `alert_rule_test` case for that `alertname` with a non-empty `exp_alerts`. Cases with only `exp_alerts: []` do not count, because they do not show that the alert can fire.

When one alert name has more than one rule, for example a warning and a critical, each rule must fire in at least one case. An expected alert matches a rule when its `exp_labels` contain every label of the rule that is not a template, for example `severity: critical`. If you test an alert name, test all of its rules; the check reports the rules that no case matches. Two rules with the same name and the same non-template labels cannot be told apart, so one firing case counts for both.

### The exception list

`tests/prometheusrules/exceptions.yaml` lists alerts that existed before this check and do not have a test yet. The goal is an empty file. The format is:

```yaml
"deploy/sre-prometheus/100-pending-csr.PrometheusRule.yaml":
  "CSRPendingLongDurationSRE": "8604986a6fc8"
```

The value is a fingerprint (a short hash) of these fields of the alert:

| Field | In the fingerprint |
|---|---|
| `expr` | Yes. Whitespace and `#` comments outside quoted strings are normalized first, so reformatting the expression or editing a comment is not a change. |
| `for` | Yes |
| `keep_firing_for` | Yes |
| `labels` | Yes |
| `annotations` | No. A text fix in a description or summary does not need a test. |

When one alert name has more than one rule in a file, the fingerprint covers all of them.

### When you add a test for an alert in the exception list

1. Add the test.
2. Remove the alert from `exceptions.yaml`. Remove the file line too if it has no alerts left.
3. Run `make test-prometheusrules`.

The check fails if an alert has a test and is still in `exceptions.yaml`. This keeps the file accurate.

### Regenerate the exception list

```bash
make test-prometheusrules ARGS=--update-exceptions
```

This rewrites `exceptions.yaml` with every alert that has no test. Only use it to remove entries after you add tests, or after you delete alerts. Reviewers should check that a pull request only removes lines from `exceptions.yaml`. A pull request that adds lines to it is adding an untested alert.

## CI failure messages

The `pr-check` job prints `PrometheusRule unit tests: FAILED` and one or more of these sections.

| Message | What it means | What to do |
|---|---|---|
| `Alerts without a unit test` | A new alert has no test case where it fires. | Add a test case to the test file named in the message. |
| `Alerts in the exception list that changed` | You changed the `expr`, `for`, `keep_firing_for` or `labels` of an alert in `exceptions.yaml`. | Add a test for the alert and remove it from `exceptions.yaml`. |
| `Alerts that have a test but are still in the exception list` | The alert is tested now. | Remove it from `exceptions.yaml`. |
| `Alerts in the exception list that no longer exist` | The alert or its rule file was renamed or deleted. | Remove it from `exceptions.yaml`. |
| `promtool test failed` | A test case does not match what the rule does. The output shows `exp` (your expectation) and `got` (what the rule produced). | Fix the test, or fix the rule if the rule is wrong. |
| `Problems in test files` | A test file is in the wrong place, points to a rule file that does not exist, lists more than one rule file, or tests an alert that the rule file does not define. | Follow the message. |

## promtool version

`Dockerfile.prow` pins `promtool` to 3.9.1. This is the Prometheus version in OCP 4.22, which is the newest OCP version in our fleet and the version on the management clusters. Older clusters run Prometheus 2.x. Prometheus 3 changed some behavior, for example range selectors no longer include the sample at the start of the range. When you update the pin, run all tests and expect some to need small changes.

## Troubleshooting

- **Platform warning on Apple silicon.** The image is `linux/amd64`. The warning `image platform (linux/amd64) does not match the expected platform` is expected, and the tests still run.
- **`statfs ... no such file or directory` with podman on macOS.** The podman machine can only mount paths under your home directory. Keep the repository under `$HOME`.

## Instructions for AI agents

Follow these steps when you add an alert, change an alert, or add tests for alerts in the exception list.

1. Read the rule file. Find every rule with the `alertname`, its `expr`, `for`, `labels` and `annotations`, and any recording rules in the same file that the `expr` uses.
2. Open or create the test file at the path from [Where test files go](#where-test-files-go). Set `rule_files` to the rule file path from the repository root.
3. Write input series with realistic labels. Use the label names that the real exporter uses (for example `kube-state-metrics` or `node-exporter`), because selectors and `on()` / `group_left()` matches depend on them.
4. Add the three cases from [What a good test checks](#what-a-good-test-checks). Expand all templates in `exp_labels` and `exp_annotations`. List every label and annotation.
5. Remove the alert from `tests/prometheusrules/exceptions.yaml` if it is there.
6. Run `make test-prometheusrules` and read the output. A `promtool test failed` result shows `exp` and `got`.
7. Do not change a rule to make a test pass, unless the task is to fix that rule. If the rule looks wrong, keep the test that shows the current behavior, and report the problem.
8. Do not add alerts to `exceptions.yaml`, and do not use `--update-exceptions` to hide a failure.
