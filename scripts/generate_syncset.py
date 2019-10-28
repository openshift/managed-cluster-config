#!/usr/bin/env python

import oyaml as yaml

import os
import sys
import argparse
import copy

managed_ann = "api.openshift.com/managed"
cluster_platform_ann = "hive.openshift.io/cluster-platform"

def get_yaml_all(filename):
    with open(filename,'r') as input_file:
        return list(yaml.safe_load_all(input_file))

def get_yaml(filename):
    with open(filename,'r') as input_file:
        return yaml.safe_load(input_file)

def get_all_yaml_files(path):
    file_paths = []
    for r,d,f in os.walk(path):
        for file in f:
            if file.endswith('.yml') or file.endswith('.yaml'):
                file_paths.append(os.path.join(r,file))
        # break, so we don't recurse
        break
    file_paths = sorted(file_paths)
    return file_paths

def get_all_yaml_obj(file_paths):
    yaml_objs = []
    for file in file_paths:
        objects = get_yaml_all(file)
        for obj in objects:
            yaml_objs.append(obj)
    return yaml_objs

def process_yamls(name, directory, syncset):
    o_gcp = copy.deepcopy(syncset)
    o_aws = copy.deepcopy(syncset)
    o_all = copy.deepcopy(syncset)
    # Get all yaml files as array of yaml objects
    yamls = get_all_yaml_obj(get_all_yaml_files(directory))
    if len(yamls) == 0:
        return

    for y in yamls:
        if 'metadata' in y:
            if 'labels' in y['metadata']:       
                if cluster_platform_ann in y['metadata']['labels']:
                    # append to specific object only
                    if y['metadata']['labels'][cluster_platform_ann] == "aws":
                        o_aws['spec']['clusterDeploymentSelector']['matchLabels'][cluster_platform_ann] = y['metadata']['labels'][cluster_platform_ann]
                    if y['metadata']['labels'][cluster_platform_ann] == "gcp":
                        o_gcp['spec']['clusterDeploymentSelector']['matchLabels'][cluster_platform_ann] = y['metadata']['labels'][cluster_platform_ann]
            else:
                o_all['spec']['clusterDeploymentSelector']['matchLabels'][managed_ann] = "true"

        

        # handle patches - patches are for all clouds (for now)
        if 'patch' in y:
            # init empty patches
            if 'patches' not in o_all['spec']:
                o_all['spec']['patches'] = []
            o_all['spec']['patches'].append(y)
        # handle resources
        else:
            # init empty resources
            if 'resources' not in o_all['spec']:
                o_all['spec']['resources'] = []
            if 'resources' not in o_gcp['spec']:
                o_gcp['spec']['resources'] = []
            if 'resources' not in o_aws['spec']:
                o_aws['spec']['resources'] = []

            # append to right object
            if "labels" in y['metadata'] and cluster_platform_ann in y['metadata']['labels']:
                # append to specific object only
                if y['metadata']['labels'][cluster_platform_ann] == "aws":
                    o_aws['spec']['resources'].append(y)
                if y['metadata']['labels'][cluster_platform_ann] == "gcp":
                     o_gcp['spec']['resources'].append(y)
            else:
                o_all['spec']['resources'].append(y)
           
    o_aws['metadata']['name'] = name+"-aws"
    o_gcp['metadata']['name'] = name+"-gcp"
    o_all['metadata']['name'] = name

    # append to right template   
    if "patches" in o_all['spec'] and len(o_all['spec']['patches']) > 0:
        template_data['objects'].append(o_aws)

    if "resources" in o_aws['spec'] and len(o_aws['spec']['resources']) > 0:
        template_data['objects'].append(o_aws)
    if "resources" in o_gcp['spec'] and len(o_gcp['spec']['resources']) > 0:
        template_data['objects'].append(o_gcp)
    if "resources" in o_all['spec'] and len(o_all['spec']['resources']) > 0:
        template_data['objects'].append(o_all)


if __name__ == '__main__':
    #Argument parser
    parser = argparse.ArgumentParser(description="selectorsyncset generation tool", usage='%(prog)s [options]')
    parser.add_argument("--template-dir", "-t", required=True, help="Path to template directory [required]")
    parser.add_argument("--yaml-directory", "-y", required=True, help="Path to folder containing yaml files [required]")
    parser.add_argument("--destination", "-d", required=True, help="Destination for selectorsynceset file [required]")
    parser.add_argument("--repo-name", "-r", required=True, help="Name of the repository [required]")
    arguments = parser.parse_args()

    # Get the template data
    template_data = get_yaml(os.path.join(arguments.template_dir, "template.yaml"))
    selectorsyncset_data = get_yaml(os.path.join(arguments.template_dir, "selectorsyncset.yaml"))

    # The templates and script are shared across repos (copy & paste).
    # Set the REPO_NAME parameter.
    for p in template_data['parameters']:
        if p['name'] == 'REPO_NAME':
            p['value'] = arguments.repo_name

    # for each subdir of yaml_directory append 'object' to template
    for (dirpath, dirnames, filenames) in os.walk(arguments.yaml_directory):
        if filenames:
            sss_name = dirpath.replace('/','-')
            if sss_name == arguments.yaml_directory:
                # files in the root dir, use repo-name for SSS name
                sss_name = arguments.repo_name
            else:
                # SSS name is based on dirpath which has the root path prefixed.. remove that prefix
                sss_name = sss_name[(len(arguments.yaml_directory) + 1):]
            process_yamls(sss_name, dirpath, selectorsyncset_data)

    # write template file ordering by keys
    with open(arguments.destination,'w') as outfile:
        yaml.dump(template_data, outfile)
