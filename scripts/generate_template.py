#!/usr/bin/env python

import oyaml as yaml

import os
import sys
import argparse
import copy
import re

cluster_platform_ann = "hive.openshift.io/cluster-platform"
config_filename = "config.yaml"

data_sss = {
    "integration": [],
    "stage": [],
    "production": []
}
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
    file_paths = sorted(file_paths, key=str.casefold)
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

    ## Get all Direct applied resources and add them to the config
    dirpaths = []
    for (dirpath, dirnames, filenames) in os.walk(arguments.yaml_directory):
        if filenames:
            dirpaths.append(dirpath)

    for dirpath in sorted(dirpaths, key=str.casefold):
        # If we're in a generated file dirpath, get the syncsets and add them
        if "__gen__" in dirpath:
            syncsets = get_all_yaml_files(dirpath)
            for syncset in syncsets:
                for environment in data_sss.keys():
                    if environment in syncset:
                        # cast syncset into a list to reuse the function here
                        for yamlobj in get_all_yaml_obj([syncset]):
                            data_sss[environment].append(yamlobj)

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

    # Get the template
    template_data = get_yaml(os.path.join(arguments.template_dir, "template.yaml"))

    # Set the REPO_NAME parameter.
    for p in template_data['parameters']:
        if p['name'] == 'REPO_NAME':
            p['value'] = arguments.repo_name

    for environment in data_resources.keys():
        # add env specific resources (in a deep copy)
        data_out = copy.deepcopy(template_data)
        for syncset in data_sss[environment]:
            data_out['objects'].append(syncset)

        for resource in data_resources[environment]:
            data_out['objects'].append(resource)

        # and write the env specific output
        with open(os.path.join(arguments.destination, "00-osd-managed-cluster-config-{}.yaml.tmpl".format(environment)), "w") as outfile:
            yaml.dump(data_out, outfile)

