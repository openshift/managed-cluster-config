#!/usr/bin/env python

import oyaml as yaml

import os
import sys
import argparse
import copy
import re

cluster_platform_ann = "hive.openshift.io/cluster-platform"
sss_config_filename = "sss-config.yaml"

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
            if (file.endswith('.yml') or file.endswith('.yaml') and not(file == sss_config_filename)):
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

def process_yamls(name, directory, obj, sss_config):
    o = copy.deepcopy(obj)

    # Set the apply mode
    if 'resourceApplyMode' in sss_config:
        o['spec']['resourceApplyMode'] = sss_config['resourceApplyMode']

    # Merge matchLabels criteria
    for key in sss_config['matchLabels']:
        if 'matchLabels' not in o['spec']['clusterDeploymentSelector']:
            o['spec']['clusterDeploymentSelector']['matchLabels'] = {}
        o['spec']['clusterDeploymentSelector']['matchLabels'][key] = sss_config['matchLabels'][key]

    # Merge matchExpressions criteria
    if 'matchExpressions' in sss_config:
        if 'matchExpressions' not in o['spec']['clusterDeploymentSelector']:
            o['spec']['clusterDeploymentSelector']['matchExpressions'] = []
        for item in sss_config['matchExpressions']:
            o['spec']['clusterDeploymentSelector']['matchExpressions'].append(item)

    # Get all yaml files as array of yaml objects
    yamls = get_all_yaml_obj(get_all_yaml_files(directory))
    if len(yamls) == 0:
        return

    for y in yamls:
        if 'patch' in y:
            if not 'patches' in o['spec']:
                o['spec']['patches'] = []
            o['spec']['patches'].append(y)
        else:
            if not 'resources' in o['spec']:
                o['spec']['resources'] = []
            o['spec']['resources'].append(y)

    o['metadata']['name'] = name
    # append object to the template's objects
    template_data['objects'].append(o)


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
    dirpaths = []
    for (dirpath, dirnames, filenames) in os.walk(arguments.yaml_directory):
        if filenames:
            dirpaths.append(dirpath)

    for dirpath in sorted(dirpaths):
        # load sss_config if it exists
        sss_config = {}
        path_sss_config = os.path.join(dirpath, sss_config_filename)
        if os.path.exists(path_sss_config):
            sss_config = get_yaml(path_sss_config)

        # initialize defaults for sss_config
        if "matchLabels" not in sss_config:
            sss_config["matchLabels"] = {}
        if "resourceApplyMode" not in sss_config:
            sss_config["resourceApplyMode"] = "Sync"

        sss_name = dirpath.replace('/','-')
        if sss_name == arguments.yaml_directory:
            # files in the root dir, use repo-name for SSS name
            sss_name = arguments.repo_name
        else:
            # SSS name is based on dirpath which has the root path prefixed.. remove that prefix
            sss_name = sss_name[(len(arguments.yaml_directory) + 1):]
            # legacy, get rid of this!
            if sss_name.startswith("UPSERT-"):
                sss_name = sss_name[7:]

        # If no matchLabelsApplyMode, process as nornmal
        if "matchLabelsApplyMode" in sss_config and sss_config["matchLabelsApplyMode"] == "OR":
            # generate new SSS per matchLabels line
            for key, value in sss_config['matchLabels'].items():

                o = copy.deepcopy(sss_config)
                o['matchLabels'].clear()
                o['matchLabels'].update({key:value})
                del o["matchLabelsApplyMode"]

                # SSS objects require unique names
                unique_sss_name = sss_name + '-' + re.sub('^.*?/', '', key)
                process_yamls(unique_sss_name, dirpath, selectorsyncset_data, o)
        else:
            # Catches anyone with a rouge value
            process_yamls(sss_name, dirpath, selectorsyncset_data, sss_config)


    # write template file ordering by keys
    with open(arguments.destination,'w') as outfile:
        yaml.dump(template_data, outfile)
