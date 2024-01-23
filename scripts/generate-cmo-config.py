#!/usr/bin/env python

import oyaml as yaml
import os

input_file_path = os.path.join("resources", "cluster-monitoring-config", "config.yaml")
output_file_path_non_uwm = os.path.join("deploy", "cluster-monitoring-config-non-uwm", "50-GENERATED-cluster-monitoring-config.yaml")
output_file_path_non_uwm_4_5 = os.path.join("deploy", "cluster-monitoring-config-non-uwm", "clusters-v4.5", "50-GENERATED-cluster-monitoring-config.yaml")

output_file_path_uwm = os.path.join("deploy", "cluster-monitoring-config", "50-GENERATED-cluster-monitoring-config.yaml")
output_file_path_fr = os.path.join("deploy", "osd-fedramp-cluster-monitoring-config", "50-GENERATED-cluster-monitoring-config.yaml")

input_mc_file_path = os.path.join("resources", "cluster-monitoring-config", "management-clusters", "config.yaml")
output_mc_file_path_non_uwm = os.path.join("deploy", "cluster-monitoring-config-non-uwm", "management-clusters", "50-GENERATED-cluster-monitoring-config.yaml")
output_mc_file_path_uwm = os.path.join("deploy", "cluster-monitoring-config", "management-clusters", "50-GENERATED-cluster-monitoring-config.yaml")


def str_presenter(dumper, data):
  if len(data.splitlines()) > 1:  # check for multiline string
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
  return dumper.represent_scalar('tag:yaml.org,2002:str', data)

yaml.add_representer(str, str_presenter)

def dump_configmap(input_path, configmap_path, enableUserWorkload, disableremoteWrite):
    with open(input_path,'r') as input_file:
        config = yaml.safe_load(input_file)
        config["enableUserWorkload"] = enableUserWorkload
        if disableremoteWrite:
           del config['prometheusK8s']['remoteWrite']
        
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

dump_configmap(input_file_path, output_file_path_uwm, True, False)
dump_configmap(input_file_path, output_file_path_non_uwm, False, False)
dump_configmap(input_file_path, output_file_path_non_uwm_4_5, False, False)
dump_configmap(input_file_path, output_file_path_fr, True, True)
dump_configmap(input_mc_file_path, output_mc_file_path_uwm, True, False)
dump_configmap(input_mc_file_path, output_mc_file_path_non_uwm, False, False)