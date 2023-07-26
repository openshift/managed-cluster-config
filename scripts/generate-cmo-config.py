#!/usr/bin/env python

import oyaml as yaml
import os

input_file_path = os.path.join("resources", "cluster-monitoring-config", "config.yaml")
output_file_path_non_uwm = os.path.join("deploy", "cluster-monitoring-config-non-uwm", "50-GENERATED-cluster-monitoring-config.yaml")
output_file_path_uwm = os.path.join("deploy", "cluster-monitoring-config", "50-GENERATED-cluster-monitoring-config.yaml")
output_file_path_fr = os.path.join("deploy", "osd-fedramp-cluster-monitoring-config", "50-GENERATED-cluster-monitoring-config.yaml")


def str_presenter(dumper, data):
  if len(data.splitlines()) > 1:  # check for multiline string
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
  return dumper.represent_scalar('tag:yaml.org,2002:str', data)

yaml.add_representer(str, str_presenter)

def dump_configmap(configmap_path, enableUserWorkload):
    with open(input_file_path,'r') as input_file:
        config = yaml.safe_load(input_file)
        config["enableUserWorkload"] = enableUserWorkload
        if remoteWrite:
           config["enableUserWorkload"] = enableUserWorkload
        
        cmo_config = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {
                "name": "cluster-monitoring-config" ,
                "namespace": "openshift-monitoring" 
            },
            "data": {
                "config.yaml": yaml.dump(config)
            }
        }
        with open(configmap_path, 'w') as outfile:
            yaml.dump(cmo_config, outfile)


dump_configmap(output_file_path_uwm, True)
dump_configmap(output_file_path_non_uwm, False)
dump_configmap(output_file_path_fr, True)