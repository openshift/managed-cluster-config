#!/usr/bin/env python
#
# Validates that all PrometheusRule alerting rules in this repository
# follow OpenShift alerting conventions, mirroring the checks from
# openshift/origin test/extended/prometheus/prometheus.go.
#
# Checks performed:
#   1. severity label must be "critical", "warning", or "info"
#   2. description and summary annotations must be present
#   3. critical alerts must have a runbook_url annotation
#   4. runbook_url must be a valid http(s) URL
#
# Pre-existing violations are tracked in per-check exception lists
# below so that the check passes for known issues while catching
# new regressions. Remove alerts from these lists as they are fixed.

import json
import os
import re
import subprocess
import sys
import tempfile
from argparse import ArgumentParser
from pathlib import Path
from urllib.parse import urlparse

import oyaml as yaml


_VALID_SEVERITY_RE = re.compile(r'^(critical|warning|info)$')

_SEARCH_DIRS = [
    Path('.', 'deploy/sre-prometheus'),
]

# Pre-existing alerts with missing or invalid severity labels.
# Remove entries as they are fixed.
_SEVERITY_EXCEPTIONS = {
    "AdditionalTrustBundleCAExpiredNotificationSRE",
    "AdditionalTrustBundleCAExpiringNotificationSRE",
    "AdditionalTrustBundleCAInvalidNotificationSRE",
    "ClusterProxyNetworkDegradedNotificationSRE",
    "ElasticsearchClusterNotHealthyNotificationSRE",
    "ElasticsearchDiskSpaceRunningLowNotificationSRE",
    "ElasticsearchNodeDiskWatermarkReachedNotificationSRE",
    "FluentdQueueLengthIncreasing",
    "FluentdQueueLengthIncreasingSRE",
    "KubeNodeUnschedulableSRE",
    "KubePersistentVolumeFillingUpSRE",
    "LoggingVolumeFillingUpNotificationSRE",
    "MultipleDefaultStorageClassesNotificationSRE",
    "MultipleIngressControllersDetectedNotificationSRE",
    "NonSystemChangeValidatingWebhookConfigurationsNotificationSRE",
    "VectorDiskBufferUsageSRE",
}

# Pre-existing alerts missing description and/or summary annotations.
# Remove entries as they are fixed.
_ANNOTATION_EXCEPTIONS = {
    "AdditionalTrustBundleCAExpiredNotificationSRE",
    "AdditionalTrustBundleCAExpiringNotificationSRE",
    "AdditionalTrustBundleCAInvalidNotificationSRE",
    "AggregatedLoggingSystemCPUHighSRE",
    "AlertmanagerSilencesActiveSRE",
    "CSRPendingLongDurationSRE",
    "CannotRetrieveUpdatesSRE",
    "CgaoInactiveHeartbeat",
    "CloudIngressOperatorOfflineSRE",
    "ClusterMonitoringErrorBudgetBurnSRE",
    "ClusterProxyNetworkDegradedNotificationSRE",
    "ConfigureAlertmanagerOperatorOfflineSRE",
    "ControlPlaneLeaderElectionFailingSRE",
    "ControlPlaneNodeFileDescriptorLimitSRE",
    "ControlPlaneNodeUnschedulableSRE",
    "ControlPlaneNodesNeedResizingSRE",
    "CsvAbnormalReplacingOver30MinSRE",
    "CsvAbnormalReplacingOver4HrSRE",
    "CustomerWorkloadPreventingDrainSRE",
    "EbsVolumeBurstBalanceLT20PctSRE",
    "EbsVolumeBurstBalanceLT40PctSRE",
    "EbsVolumeStuckAttaching10MinSRE",
    "EbsVolumeStuckAttaching5MinSRE",
    "EbsVolumeStuckDetaching10MinSRE",
    "EbsVolumeStuckDetaching5MinSRE",
    "ElasticsearchClusterNotHealthyNotificationSRE",
    "ElasticsearchClusterNotHealthySRE",
    "ElasticsearchDiskNeedsResizingSRE",
    "ElasticsearchDiskSpaceRunningLowNotificationSRE",
    "ElasticsearchDiskSpaceRunningLowSRE",
    "ElasticsearchHighFileDescriptorUsageSRE",
    "ElasticsearchJVMHeapUseHighSRE",
    "ElasticsearchJobFailedSRE",
    "ElasticsearchNodeDiskWatermarkReachedNotificationSRE",
    "ElasticsearchNodeDiskWatermarkReachedSRE",
    "ElasticsearchOperatorCSVNotSuccessfulSRE",
    "ElasticsearchProcessCPUHighSRE",
    "ElasticsearchWriteRequestsRejectionJumpsSRE",
    "ElevatingClusterAdminRHMISRE",
    "ElevatingClusterAdminRHOAMSRE",
    "ExcessiveContainerMemoryCriticalSRE",
    "ExcessiveContainerMemoryWarningSRE",
    "FedRAMPNodeFilesystemSpaceFillingUp",
    "FluentDHighErrorRate",
    "FluentDHighErrorRateSRE",
    "FluentDVeryHighErrorRate",
    "FluentDVeryHighErrorRateSRE",
    "FluentdNodeDown",
    "FluentdNodeDownSRE",
    "FluentdQueueLengthIncreasing",
    "FluentdQueueLengthIncreasingSRE",
    "HAProxyReloadFailSRE",
    "InfraNodesNeedResizingSRE",
    "KubeAPIServerMissingOnNode60Minutes",
    "KubeControllerManagerMissingOnNode60Minutes",
    "KubeNodeStuckWithCreatingAndTerminatingPodsSRE",
    "KubeNodeUnschedulableSRE",
    "KubePersistentVolumeFillingUpSRE",
    "KubePersistentVolumeFullInFourDaysCustomer",
    "KubePersistentVolumeFullInFourDaysLayeredProduct",
    "KubePersistentVolumeUsageCriticalCustomer",
    "KubePersistentVolumeUsageCriticalLayeredProduct",
    "KubeQuotaExceededSRE",
    "KubeSchedulerMissingOnNode60Minutes",
    "KubeletDebuggingHandlersEnabledSRE",
    "LoggingVolumeFillingUpNotificationSRE",
    "MNMOTooManyReconcileErrors15MinSRE",
    "MachineOutOfComplianceSRE",
    "MetricsClientSendFailingSRE",
    "MultipleDefaultStorageClassesNotificationSRE",
    "MultipleIngressControllersDetectedNotificationSRE",
    "MultipleVersionsOfEFSCSIDriverInstalled",
    "NetworkMigrationBlocked",
    "NetworkMigrationDelayedSRE",
    "NodeConditionDiskPressureNotificationSRE",
    "NodeConditionMemoryPressureNotificationSRE",
    "NodeConditionNetworkUnavailableNotificationSRE",
    "NodeConditionPIDPressureNotificationSRE",
    "NonSystemChangeValidatingWebhookConfigurationsNotificationSRE",
    "OCMAgentOperatorPullSecretInvalidSRE",
    "OCMAgentPullSecretInvalidSRE",
    "OCMAgentResponseFailureServiceLogsSRE",
    "OCMAgentServiceLogsSentExceedingLimit",
    "PodDisruptionBudgetLimitSRE",
    "PruningCronjobErrorSRE",
    "RouterAvailabilityLT30PctSRE",
    "RouterAvailabilityLT50PctSRE",
    "RunawaySDNPreventingContainerCreationSRE",
    "SLAUptimeSRE",
    "UpgradeConfigSyncFailureOver4HrSRE",
    "UpgradeConfigValidationFailedSRE",
    "UpgradeControlPlaneUpgradeTimeoutSRE",
    "UpgradeNodeDrainFailedSRE",
    "UpgradeNodeUpgradeTimeoutSRE",
    "UserWorkloadMonitoringErrorBudgetBurn",
    "VeleroDailyFullBackupMissed",
    "VeleroHourlyObjectBackupsMissedConsecutively",
    "VeleroWeeklyFullBackupMissed",
    "VpcEndpointPendingAcceptance",
    "WorkerNodeFileDescriptorLimitSRE",
    "cpu-InfraNodesExcessiveResourceConsumptionSRE",
    "cpu-InfraNodesExcessiveResourceConsumptionSRE1h",
    "memory-InfraNodesExcessiveResourceConsumptionSRE",
}

# Pre-existing critical alerts missing runbook_url.
# Remove entries as they are fixed.
_RUNBOOK_URL_EXCEPTIONS = {
    "CannotRetrieveUpdatesSRE",
    "CgaoInactiveHeartbeat",
    "CloudIngressOperatorOfflineSRE",
    "ClusterMonitoringErrorBudgetBurnSRE",
    "ConfigureAlertmanagerOperatorOfflineSRE",
    "ControlPlaneNodeFileDescriptorLimitSRE",
    "ControlPlaneNodeUnschedulableSRE",
    "ControlPlaneNodesNeedResizingSRE",
    "CsvAbnormalReplacingOver4HrSRE",
    "CustomerWorkloadPreventingDrainSRE",
    "EbsVolumeBurstBalanceLT20PctSRE",
    "EbsVolumeStuckAttaching10MinSRE",
    "EbsVolumeStuckDetaching10MinSRE",
    "ElasticsearchClusterNotHealthySRE",
    "ElasticsearchDiskNeedsResizingSRE",
    "ExcessiveContainerMemoryCriticalSRE",
    "FedRAMPNodeFilesystemSpaceFillingUp",
    "FluentDVeryHighErrorRate",
    "FluentDVeryHighErrorRateSRE",
    "FluentdNodeDown",
    "FluentdNodeDownSRE",
    "HAProxyDownSRE",
    "HAProxyDownSRENonDefault",
    "InfraNodesNeedResizingSRE",
    "InsightsOperatorDownSRE",
    "KubeControllerManagerMissingOnNode60Minutes",
    "KubePersistentVolumeUsageCriticalCustomer",
    "KubePersistentVolumeUsageCriticalLayeredProduct",
    "KubeletDebuggingHandlersEnabledSRE",
    "MachineHealthCheckUnterminatedShortCircuitSRE",
    "MachineOutOfComplianceSRE",
    "MetricsClientSendFailingSRE",
    "MultipleVersionsOfEFSCSIDriverInstalled",
    "NetworkMigrationDelayedSRE",
    "NodepoolFailureNotification",
    "OCMAgentResponseFailureServiceLogsSRE",
    "PodDisruptionBudgetLimitSRE",
    "PruningCronjobErrorSRE",
    "RouterAvailabilityLT30PctSRE",
    "RunawaySDNPreventingContainerCreationSRE",
    "SLAUptimeSRE",
    "UpgradeConfigSyncFailureOver4HrSRE",
    "UpgradeConfigValidationFailedSRE",
    "UpgradeControlPlaneUpgradeTimeoutSRE",
    "UpgradeNodeDrainFailedSRE",
    "UpgradeNodeUpgradeTimeoutSRE",
    "UserWorkloadMonitoringErrorBudgetBurn",
    "VpcEndpointPendingAcceptance",
    "WorkerNodeFileDescriptorLimitSRE",
}


def _find_prometheusrule_files(directories):
    files = []
    errors = []
    for directory in directories:
        for root, _, entries in os.walk(directory):
            for entry in entries:
                path = Path(root, entry)
                if path.suffix not in ('.yml', '.yaml'):
                    continue
                try:
                    with path.open() as f:
                        content = f.read()
                    doc = yaml.safe_load(content)
                    if (isinstance(doc, dict)
                            and doc.get('kind') == 'PrometheusRule'
                            and doc.get('apiVersion') == 'monitoring.coreos.com/v1'):
                        files.append((path, doc))
                except yaml.YAMLError as e:
                    if 'kind: PrometheusRule' in content:
                        errors.append(f"{path}: {e}")
                except OSError as e:
                    errors.append(f"{path}: {e}")
    return files, errors

def _extract_alerting_rules(doc):
    rules = []
    for group in doc.get('spec', {}).get('groups', []):
        group_name = group.get('name', '<unnamed>')
        for rule in group.get('rules', []):
            if 'alert' in rule:
                rules.append((group_name, rule))
    return rules


def _check_severity(alert_name, rule):
    if alert_name in _SEVERITY_EXCEPTIONS:
        return []

    violations = []
    labels = rule.get('labels', {})
    severity = labels.get('severity')

    if severity is None:
        violations.append("has no 'severity' label")
    elif not _VALID_SEVERITY_RE.match(str(severity)):
        violations.append(
            f"has a 'severity' label value of '{severity}' which doesn't match "
            f"'^(critical|warning|info)$'"
        )
    return violations


def _check_annotations(alert_name, rule):
    if alert_name in _ANNOTATION_EXCEPTIONS:
        return []

    violations = []
    annotations = rule.get('annotations', {})

    if 'description' not in annotations:
        if 'message' in annotations:
            violations.append(
                "has no 'description' annotation, but has a 'message' annotation. "
                "OpenShift alerts must use 'description' -- consider renaming the annotation"
            )
        else:
            violations.append("has no 'description' annotation")

    if 'summary' not in annotations:
        violations.append("has no 'summary' annotation")

    return violations


def _check_namespace(alert_name, rule):
    labels = rule.get('labels', {}) or {}
    if labels.get('namespace') is None:
        return ["has no 'namespace' label"]
    return []


def _check_runbook_url(alert_name, rule):
    violations = []
    labels = rule.get('labels', {})
    annotations = rule.get('annotations', {})
    severity = str(labels.get('severity', ''))

    runbook_url = str(annotations.get('runbook_url', ''))

    if severity == 'critical' and not runbook_url:
        if alert_name not in _RUNBOOK_URL_EXCEPTIONS:
            violations.append(
                "is a critical alert with no 'runbook_url' annotation"
            )

    if runbook_url:
        try:
            parsed = urlparse(runbook_url)
            if parsed.scheme not in ('http', 'https'):
                violations.append(
                    f"has a 'runbook_url' with invalid scheme '{parsed.scheme}', "
                    f"expected 'http' or 'https'"
                )
            elif not parsed.hostname:
                violations.append(
                    "has a 'runbook_url' with an empty host"
                )
        except Exception:
            violations.append(
                f"has a 'runbook_url' that is not a valid URL: '{runbook_url}'"
            )

    return violations


_CHECKS = [
    _check_severity,
    _check_annotations,
    _check_runbook_url,
    _check_namespace,
]


def _run_promtool(path, doc):
    spec = doc.get('spec', {})
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(spec, f)
        tmp_path = f.name
    try:
        result = subprocess.run(
            ['promtool', 'check', 'rules', '--lint=all', '--lint-fatal', tmp_path],
            capture_output=True,
            text=True,
        )
    finally:
        os.unlink(tmp_path)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        return f"  {path}: promtool validation failed: {detail}"
    return None


def main():
    parser = ArgumentParser(
        description='Validate PrometheusRule alerting conventions'
    )
    parser.add_argument(
        '--directories',
        nargs='*',
        type=Path,
        default=_SEARCH_DIRS,
        help='Directories to search for PrometheusRule YAML files',
    )
    args = parser.parse_args()

    prom_files, file_errors = _find_prometheusrule_files(args.directories)
    if file_errors:
        for err in file_errors:
            print(f'  {err}')
        sys.exit(1)
    if not prom_files:
        print('No PrometheusRule files found.')
        return

    all_violations = []

    for path, doc in prom_files:
        alerting_rules = _extract_alerting_rules(doc)
        for group_name, rule in alerting_rules:
            alert_name = rule.get('alert', '<unnamed>')
            for check in _CHECKS:
                for violation in check(alert_name, rule):
                    all_violations.append(
                        f'  {path}: alerting rule "{alert_name}" '
                        f'(group: {group_name}) {violation}'
                    )

        promtool_error = _run_promtool(path, doc)
        if promtool_error:
            all_violations.append(promtool_error)

    if all_violations:
        print(f'PrometheusRule check: FAILED ({len(all_violations)} violations)\n')
        for v in all_violations:
            print(v)
        sys.exit(1)

    print(f'PrometheusRule check: PASSED ({len(prom_files)} files checked)')


if __name__ == '__main__':
    main()
