#!/usr/bin/env python

import subprocess
import sys
import json
import argparse
import textwrap
import oyaml as yaml

CONFIGMAP_TEMPLATE = """apiVersion: v1
kind: ConfigMap
metadata:
  name: {}
  namespace: {}
data:
  managed_resources.yaml: |
{}
"""


def get_api_resource_kinds():
    """
    Returns a list of of api-resources from the logged-in cluster
    """
    try:
        r = subprocess.check_output(
            ["oc", "api-resources", "-o", "name"], stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError as e:
        sys.exit(f"Failed to get a list of api-resources: {e}")

    return [i.decode("utf-8") for i in r.splitlines()]


def collect_managed_resources(kinds):
    """
    Given a list of resource kinds, returns a dictionary of the managed resources for each kind
    """
    resources = dict()
    managed_label = "hive.openshift.io/managed=true"
    keys_to_extract = ["namespace", "name"]
    for kind in kinds:
        print("Collecting {}...".format(kind))
        result = subprocess.run(
            [
                "oc",
                "get",
                "--ignore-not-found",
                kind,
                "-A",
                "-o",
                "json",
                "-l",
                managed_label,
            ],
            capture_output=True,
        )
        if len(result.stdout) == 0 or result.returncode != 0:
            continue
        kind_dict = json.loads(result.stdout)
        if len(kind_dict["items"]) > 0:
            kind_name = kind_dict["items"][0]["kind"]
            filtered_kind_list = [
                {
                    key: i["metadata"][key]
                    for key in keys_to_extract
                    if i["metadata"].get(key) is not None
                }
                for i in kind_dict["items"]
            ]
            resources[kind_name] = filtered_kind_list
    return resources


def main():
    parser = argparse.ArgumentParser(
        description="Collects all hive-managed resources from a cluster and outputs them as yaml documents"
    )
    parser.add_argument(
        "--path",
        "-p",
        required=True,
        help="Destination file path for artifact [required]",
    )
    parser.add_argument(
        "--output",
        "-o",
        required=True,
        choices=["yaml", "configmap"],
        help="Output format of managed resource list [required]",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Output ALL managed resources. By default, it only outputs namespaces.",
    )
    parser.add_argument(
        "--namespace",
        "-ns",
        default="openshift-monitoring",
        help="The namespace for the generated ConfigMap",
    )
    parser.add_argument(
        "--name",
        default="managed-namespaces",
        help="The name of the generated ConfigMap",
    )
    arguments = parser.parse_args()
    try:
        r = subprocess.check_output(["oc", "whoami"], stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as e:
        sys.exit(
            "Must be logged into an OSD cluster to gather list of managed resources"
        )
    print("Collecting a list of hive-managed resources from cluster...")
    if arguments.all:
        kinds = get_api_resource_kinds()
    else:
        kinds = ["namespaces"]
    managed_resource_dict = collect_managed_resources(kinds)
    managed_resource_yaml = yaml.dump(managed_resource_dict)
    with open(arguments.path, "w") as f:
        if arguments.output == "yaml":
            f.write(managed_resource_yaml)
        else:
            # indent the yaml document into the configmap template
            f.write(
                CONFIGMAP_TEMPLATE.format(
                    arguments.name,
                    arguments.namespace,
                    textwrap.indent(managed_resource_yaml, "    "),
                )
            )


if __name__ == "__main__":
    main()
