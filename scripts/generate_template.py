#!/usr/bin/env python

import oyaml as yaml

import os
import sys
import argparse
import copy
import re

cluster_platform_ann = "hive.openshift.io/cluster-platform"
config_filename = "config.yaml"

data_sss = []
data_resources = {
    "integration": [],
    "stage": [],
    "production": []
}

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
            if (file.endswith('.yml') or file.endswith('.yaml') and not(file == config_filename)):
                file_paths.append(os.path.join(r,file))
        # break, so we don't recurse
        break
    file_paths = sorted(file_paths)
    return file_paths

def get_all_yaml_obj(file_paths):
    yaml_objs = []
    for file in file_paths:
        raw_objects = get_yaml_all(file)
        # remove None results (happens if a yaml has '---' at the end)
        objects = [o for o in raw_objects if o] 

        for obj in objects:
            yaml_objs.append(obj)
    return yaml_objs

def add_sss_for(name, directory, config):
    # grab a deep copy of the template and configure it
    sss_template = get_yaml(os.path.join(arguments.template_dir, "selectorsyncset.yaml"))
    o = copy.deepcopy(sss_template)

    # Set the apply mode
    if 'resourceApplyMode' in config:
        o['spec']['resourceApplyMode'] = config['resourceApplyMode']

    if 'applyBehavior' in config:
        o['spec']['applyBehavior'] = config['applyBehavior']

    # Merge matchLabels criteria
    for key in config['matchLabels']:
        if 'matchLabels' not in o['spec']['clusterDeploymentSelector']:
            o['spec']['clusterDeploymentSelector']['matchLabels'] = {}
        o['spec']['clusterDeploymentSelector']['matchLabels'][key] = config['matchLabels'][key]

    # Merge matchExpressions criteria
    if 'matchExpressions' in config:
        if 'matchExpressions' not in o['spec']['clusterDeploymentSelector']:
            o['spec']['clusterDeploymentSelector']['matchExpressions'] = []
        for item in config['matchExpressions']:
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
    
    # collect the new sss for later processing
    data_sss.append(o)

def add_resources_for(directory, config):
    # there isn't a template, only thing we really care about is the environments and simply add each resource to each of those environments.
    # at this point the properties we care about are _required_
    yamls = get_all_yaml_obj(get_all_yaml_files(directory))
    if len(yamls) == 0:
        return

    for y in yamls:
        for environment in config["environments"]:
            data_resources[environment].append(y)


if __name__ == '__main__':
    #Argument parser
    parser = argparse.ArgumentParser(description="template generation tool", usage='%(prog)s [options]')
    parser.add_argument("--template-dir", "-t", required=True, help="Path to template directory [required]")
    parser.add_argument("--yaml-directory", "-y", required=True, help="Path to folder containing yaml files [required]")
    parser.add_argument("--destination", "-d", required=True, help="Destination directory for template files [required]")
    parser.add_argument("--repo-name", "-r", required=True, help="Name of the repository [required]")
    arguments = parser.parse_args()

    dirpaths = []
    for (dirpath, dirnames, filenames) in os.walk(arguments.yaml_directory):
        if filenames:
            dirpaths.append(dirpath)

    for dirpath in sorted(dirpaths):
        # load config if it exists
        config = {}
        path_config = os.path.join(dirpath, config_filename)
        if os.path.exists(path_config):
            config = get_yaml(path_config)

        deploymentMode = "SelectorSyncSet"

        if "deploymentMode" in config:
            deploymentMode = config["deploymentMode"]

        if deploymentMode == "Direct":
            add_resources_for(dirpath, config["direct"])

        elif deploymentMode == "SelectorSyncSet":
            # initialize defaults for config
            if "selectorSyncSet" not in config:
                config["selectorSyncSet"] = {}
            if "matchLabels" not in config["selectorSyncSet"]:
                config["selectorSyncSet"]["matchLabels"] = {}
            if "resourceApplyMode" not in config["selectorSyncSet"]:
                config["selectorSyncSet"]["resourceApplyMode"] = "Sync"
            # NOTE we do not set applyBehavior if not provided, we fall back on hive defaults

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
            if "matchLabelsApplyMode" in config["selectorSyncSet"] and config["selectorSyncSet"]["matchLabelsApplyMode"] == "OR":
                # generate new SSS per matchLabels line
                for key, value in config["selectorSyncSet"]['matchLabels'].items():

                    o = copy.deepcopy(config)
                    o["selectorSyncSet"]['matchLabels'].clear()
                    o["selectorSyncSet"]['matchLabels'].update({key:value})
                    del o["selectorSyncSet"]["matchLabelsApplyMode"]

                    # SSS objects require unique names
                    unique_sss_name = sss_name + '-' + re.sub('^.*?/', '', key)
                    add_sss_for(unique_sss_name, dirpath, o["selectorSyncSet"])
            else:
                # Catches anyone with a rouge value
                add_sss_for(sss_name, dirpath, config["selectorSyncSet"])

    # Get the template 
    template_data = get_yaml(os.path.join(arguments.template_dir, "template.yaml"))

    # Set the REPO_NAME parameter.
    for p in template_data['parameters']:
        if p['name'] == 'REPO_NAME':
            p['value'] = arguments.repo_name

    # add all SSS to the base template (it's the same for all environments)
    for sss in data_sss:
        template_data['objects'].append(sss)

    for environment in data_resources.keys():
        # add env specific resources (in a deep copy)
        data_out = copy.deepcopy(template_data)
        for resource in data_resources[environment]:
            data_out['objects'].append(resource)

        # and write the env specific output
        with open(os.path.join(arguments.destination, "00-osd-managed-cluster-config-{}.yaml.tmpl".format(environment)), "w") as outfile:
            yaml.dump(data_out, outfile)

