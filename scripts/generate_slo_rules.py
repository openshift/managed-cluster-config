#!/usr/bin/env python3
"""
SLO Monitoring Prometheus Rule File Generator

Translates a CSV with rules in it into properly-formatted PrometheusRule.yaml files.

Run with -h flag to see full usage details.
"""
import yaml
import csv
import sys
from os.path import join
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter

CSV_DESCRIPTION = """This script translates a standard CSV file into a collection of properly formatted 
PrometheusRule.yaml files. The input CSV file must have the following column headers 
in the first row:
category:    a short whitespace-free string describing what category of SLO each row falls
             into, e.g. 'control-plane' or 'compute'
             
slo:         the percentage, expressed as a float between 0 and 1, that is the lower bound
             of the 28-day availability SLO, e.g. '0.999' for 99.9%
             
tech_name:   a whitespace-free string that can serve as a prefix to the name of the rules
             that will be generated by this rule, e.g. 'sli:control_plane_alerts'
             
up_rule:     a PromQL expression that will return 1 if the SLI is within its nominal range
             at that point in time, otherwise it will return 0. This field may be left 
             blank. The resulting rule will take the name "<tech_name>:up"
             
uptime_rule: a PromQL expression expression that returns the percentage, expressed as a
             float between 0 and 1, of the 28-day 'error-budget' remaining. The resulting
             rule will take the name "<tech_name>:uptime:28d"
             
alert_name_prefix: a short whitespace-free string that will prefix the names of the alerting
             rules generated by each row, e.g. 'SLOControlPlaneAlerts'. The resulting alerts 
             will end with the strings 'LT10PctSRE', 'LT20PctSRE', and 'ViolatedSRE'

Example of a valid CSV file:
category,slo,tech_name,up_rule,uptime_rule,alert_name_prefix
registry,0.99,sli:registry_api,,"valid_promql",SLORegistryApi

This example would produce 4 rules:
  - name: sre-slo-registry.rules
    rules:
    - expr: valid_promql
      record: sli:registry_api:uptime:28d
  - name: sre-slo-registry.alerts
    rules:
    - alert: SLORegistryApiLT20PctSRE
      expr: sli:registry_api:uptime:28d < 0.992
      labels:
        severity: warning
    - alert: SLORegistryApiLT10PctSRE
      expr: sli:registry_api:uptime:28d < 0.991
      labels:
        severity: critical
    - alert: SLORegistryApiViolatedSRE
      expr: sli:registry_api:uptime:28d < 0.99
      labels:
        severity: critical"""

TEMPLATE = """
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    prometheus: sre-slo-xyz
    role: alert-rules
  name: sre-slo-xyz
  namespace: openshift-monitoring
spec:
  groups:
  - name: sre-slo-xyz.rules
    rules: []
  - name: sre-slo-xyz.alerts
    rules: []
"""

# If CSV help is requested, print that and exit
if "-c" in sys.argv or "--help-csv" in sys.argv:
    print(CSV_DESCRIPTION)
    sys.exit()

# Handle command line args
argp = ArgumentParser(
    formatter_class=ArgumentDefaultsHelpFormatter,
    description="This script translates a standard CSV file into a collection of properly formatted PrometheusRule.yaml files. See the -c flag for how to format the CSV input file",
)

argp.add_argument(
    "csv_path", help="CSV file containing rules in a machine-readable format."
)
argp.add_argument(
    "-c", "--help-csv", help="Print help information about the input file format"
)
argp.add_argument(
    "-o", "--output", help="Directory to put the resulting rule files.", default="./"
)
argp.add_argument(
    "-f",
    "--format",
    help="Python 3 format string for the rule filenames. Use {} as the symbol for the rule category.",
    default="100-slo-{}.PrometheusRule.yaml",
)
args = argp.parse_args()

output = {}

# Open input file
with open(args.csv_path, mode="r", newline="") as csvfile:
    reader = csv.DictReader(csvfile)
    for raw_row in reader:
        row = {key: val.strip() for key, val in raw_row.items()}
        try:
            o = output[row["category"]]
        except KeyError:
            output[row["category"]] = yaml.safe_load(TEMPLATE)
            o = output[row["category"]]
            o["metadata"]["labels"]["prometheus"] = "sre-slo-" + row["category"]
            o["metadata"]["name"] = "sre-slo-" + row["category"]
            o["spec"]["groups"][0]["name"] = "sre-slo-{}.rules".format(row["category"])
            o["spec"]["groups"][1]["name"] = "sre-slo-{}.alerts".format(row["category"])

        # First, add the necessary recording rules
        if len(row["up_rule"]) > 1:
            # Not all SLOs have up rules
            o["spec"]["groups"][0]["rules"].append(
                {"record": row["tech_name"] + ":up", "expr": row["up_rule"]}
            )
        o["spec"]["groups"][0]["rules"].append(
            {"record": row["tech_name"] + ":uptime:28d", "expr": row["uptime_rule"]}
        )

        # Then add the warning alerting rule
        warn_thresh = round(float(row["slo"]) + ((1.0 - float(row["slo"])) * 0.2), 8)
        o["spec"]["groups"][1]["rules"].append(
            {
                "alert": row["alert_name_prefix"] + "LT20PctSRE",
                "expr": "{}:uptime:28d < {}".format(row["tech_name"], warn_thresh),
                "labels": {"severity": "warning"},
            }
        )

        # Then the critical alerting rule
        crit_thresh = round(float(row["slo"]) + ((1.0 - float(row["slo"])) * 0.1), 8)
        o["spec"]["groups"][1]["rules"].append(
            {
                "alert": row["alert_name_prefix"] + "LT10PctSRE",
                "expr": "{}:uptime:28d < {}".format(row["tech_name"], crit_thresh),
                "labels": {"severity": "critical"},
            }
        )
        
        # Then the violation alerting rule
        o["spec"]["groups"][1]["rules"].append(
            {
                "alert": row["alert_name_prefix"] + "ViolatedSRE",
                "expr": "{}:uptime:28d < {}".format(row["tech_name"], float(row["slo"])),
                "labels": {"severity": "critical"},
            }
        )

# Write rule files
for category, content in output.items():
    filename = join(args.output, args.format.format(category))
    with open(filename, "w") as f:
        yaml.dump(content, f, width=95)

