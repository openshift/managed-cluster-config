#!/usr/bin/env python3

import json
import oyaml as yaml
import textwrap

CONFIGMAP_TEMPLATE = """apiVersion: v1
kind: ConfigMap
metadata:
  name: managed-resources-map
  namespace: openshift-monitoring
data:
  managed_resources.yaml: |
{}
"""


def main():
    """
    Read the file containing resources with the managed label and
    generate a configmap containing those resources
    """

    with open("/tmp/output.log", "r") as resource_list:
        with open("managed-resources.ConfigMap.yaml", "w") as configmap:
            resources = dict()
            keys_to_extract = ["namespace", "name"]
            lines = resource_list.readlines()
            for line in lines:
                resource = json.loads(line)
                entry = {
                    key: resource[key]
                    for key in keys_to_extract
                    if resource[key] is not None
                }
                if resource["kind"] in resources:
                    resources[resource["kind"]].append(entry)
                else:
                    resources[resource["kind"]] = [entry]
            resources_yaml = yaml.dump(resources)
            configmap.write(
                CONFIGMAP_TEMPLATE.format(textwrap.indent(resources_yaml, "    "))
            )


if __name__ == "__main__":
    main()
