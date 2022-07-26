#!/usr/bin/env python

import subprocess
import sys
import json
import argparse
import textwrap
import tempfile
import os
import oyaml as yaml

CONFIGMAP_TEMPLATE = """apiVersion: v1
kind: ConfigMap
metadata:
  name: {}
  namespace: {}
data:
  managed_namespaces.yaml: |
{}
"""

# This is a list of namespaces that do not have the "hive.openshift.io/managed=true" label but
# are still being managed by SRE-P.
ADDITIONAL_MANAGED_NAMESPACES = [
    {"name": "openshift-monitoring"},
    {"name": "openshift"},
    {"name": "openshift-cluster-version"}
]


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


def collect_ocp_release_namespaces():
    """
    Returns a dict of namespaces present in the manifests provided by 'ocm adm release extract'
    """
    ocp_namespaces = []
    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            r = subprocess.check_output(
                ["oc", "adm", "release", "extract", "--to", tmpdir],
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError as e:
            sys.exit(f"Failed to extract OCP release manifests: {e}")
        yaml_file_paths = [
            os.path.join(tmpdir, f) for f in os.listdir(tmpdir) if f.endswith(".yaml")
        ]
        # make sure a bare = sign doesn't break our loader
        # temporary fix for https://github.com/yaml/pyyaml/issues/89
        yaml.FullLoader.yaml_implicit_resolvers.pop('=')
        for file_path in yaml_file_paths:
            with open(file_path, "r") as f:
                manifests = yaml.full_load_all(f)
                for manifest in manifests:
                    if manifest is not None and manifest["kind"] == "Namespace":
                        ocp_namespaces.append(manifest["metadata"]["name"])
    resources = dict()
    resources["Resources"] = {}
    # Add in clusteroperator relatedobject namespaces
    co_namespaces = collect_clusteroperator_relatedobjects()
    ocp_namespaces.extend(co_namespaces)
    ocp_namespaces = list(set(ocp_namespaces))
    ocp_namespaces.sort()

    resources["Resources"]["Namespace"] = [{"name": ns} for ns in ocp_namespaces]
    return resources


def collect_clusteroperator_relatedobjects():
    """
    Returns a list of every namespace listed as a relatedObject by every clusterOperator. This captures
    managed namespaces that aren't defined in the OCP manifests.
    """
    co_namespaces = []
    try:
        result = subprocess.run(["oc", "get", "co", "-o", "name"], capture_output=True)
    except subprocess.CalledProcessError as e:
        sys.exit(f"Failed to get list of installed cluster operators: {e}")
    for n in result.stdout.splitlines():
        r = subprocess.run(["oc", "get", n, "-o", "json"], capture_output=True)
        operator_dict = json.loads(r.stdout)
        related_namespaces = [
            ns["name"]
            for ns in operator_dict["status"]["relatedObjects"]
            if ns["resource"] == "namespaces"
        ]
        co_namespaces.extend(related_namespaces)
    return co_namespaces


def collect_managed_resources(kinds):
    """
    Given a list of resource kinds, returns a dictionary of the managed resources for each kind
    """
    resources = dict()
    resources["Resources"] = {}
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
            resources["Resources"][kind_name] = filtered_kind_list
    resources = remove_backplane_service_account(resources)
    resources["Resources"]["Namespace"] += ADDITIONAL_MANAGED_NAMESPACES
    return resources


def remove_backplane_service_account(resource_dict):
    """
    Replace the generated serviceaccount name for backplane users and replace with a generic value
    """
    # if there aren't any serviceaccounts, return the dictionary unchanged.
    if "ServiceAccount" not in resource_dict["Resources"]:
        return resource_dict
    # get unique backplane serviceaccount id
    backplane_sacct_id = (
        subprocess.check_output(["oc", "whoami"])
        .decode("utf-8")
        .split(":")[-1]
        .rstrip()
    )
    backplane_sa_list_entry = {
        "namespace": "openshift-backplane-srep",
        "name": backplane_sacct_id,
    }
    # replace backplane service account id with a generic value
    if backplane_sa_list_entry in resource_dict["Resources"]["ServiceAccount"]:
        resource_dict["Resources"]["ServiceAccount"].remove(backplane_sa_list_entry)
        resource_dict["Resources"]["ServiceAccount"].append(
            {
                "namespace": "openshift-backplane-srep",
                "name": "UNIQUE_BACKPLANE_SERVICEACCOUNT_ID",
            }
        )
    return resource_dict


def save_output_to_disk(arguments, file_contents):
    with open(arguments.path, "w") as f:
        if arguments.output == "yaml":
            f.write(file_contents)
        else:
            # indent the yaml document into the configmap template
            f.write(
                CONFIGMAP_TEMPLATE.format(
                    arguments.name,
                    arguments.namespace,
                    textwrap.indent(file_contents, "    "),
                )
            )


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
        "--source",
        "-s",
        required=True,
        choices=["osd-all", "osd-namespaces", "ocp-namespaces"],
        help="Choose to output all OSD managed resources, or just the managed namespaces for OSD or OCP [required]",
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
    if arguments.source in ["osd-all", "osd-namespaces"]:
        print("Collecting a list of hive-managed resources from cluster...")
        if arguments.source == "osd-all":
            kinds = get_api_resource_kinds()
        else:
            kinds = ["namespaces"]
        managed_resource_dict = collect_managed_resources(kinds)
        managed_resource_yaml = yaml.dump(managed_resource_dict)
        save_output_to_disk(arguments, managed_resource_yaml)
    elif arguments.source == "ocp-namespaces":
        managed_ocp_resource_dict = collect_ocp_release_namespaces()
        managed_ocp_resource_yaml = yaml.dump(managed_ocp_resource_dict)
        save_output_to_disk(arguments, managed_ocp_resource_yaml)


if __name__ == "__main__":
    main()
