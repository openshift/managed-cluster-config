#!/usr/bin/env python

import oyaml as yaml

import os
import sys
import argparse
import copy
import re

config_filename = "config.yaml"

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

def add_sss_for(name, directory, environments, config):
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

    # write the new SSS in that components `__gen__` directory
    gen_dir = os.path.join(directory, "__gen__")

    if not os.path.exists(gen_dir):
        print("Creating directory {}".format(gen_dir))
        os.mkdir(gen_dir)

    for env in environments:
        sss_filename="{name}_{env}.yaml".format_map({
            "name": name,
            "env": env,
        })
        with open(os.path.join(gen_dir, sss_filename), "w") as outfile:
            yaml.dump(o, outfile)

if __name__ == '__main__':
    #Argument parser
    parser = argparse.ArgumentParser(description="component generation tool", usage='%(prog)s [options]')
    parser.add_argument("--template-dir", "-t", required=True, help="Path to template directory [required]")
    parser.add_argument("--yaml-directory", "-y", required=True, help="Path to folder containing yaml files [required]")
    parser.add_argument("--repo-name", "-r", required=True, help="Name of the repository [required]")
    parser.add_argument("--environment", "-e", default="int,stage", help="Comma delimited list of environments to generate the component data for")
    parser.add_argument("--component", "-c", default="__ALL__", help="Single component to generate data for. Used mostly for promoting a single component to prod")
    arguments = parser.parse_args()

    environments = []
    for env in arguments.environment.split(","):
        int_envs = ["i", "int", "integration"]
        stg_envs = ["s", "stg", "stage", "staging"]
        prd_envs = ["p", "prd", "prod", "production"]

        if env in int_envs:
            environments.append("integration")

        if env in stg_envs:
            environments.append("stage")

        if env in prd_envs:
            environments.append("production")

    dirpaths = []
    if arguments.component == "__ALL__":
        for (dirpath, dirnames, filenames) in os.walk(arguments.yaml_directory):
            # we want to ignore any __gen__ directories
            if "__gen__" in dirpath:
                continue

            if filenames:
                dirpaths.append(dirpath)
    else:
        component_path = os.path.join("deploy", arguments.component)
        if not os.path.exists(component_path):
            print("Component path {} doesn't exist.".format(component_path))

        dirpaths.append(component_path)


    for dirpath in sorted(dirpaths, key=str.casefold):
        # load config if it exists
        config = {}
        path_config = os.path.join(dirpath, config_filename)
        if os.path.exists(path_config):
            config = get_yaml(path_config)

        deploymentMode = "SelectorSyncSet"

        if "deploymentMode" in config:
            deploymentMode = config["deploymentMode"]

        if deploymentMode != "SelectorSyncSet":
            continue

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
            if 'matchLabels' in config["selectorSyncSet"]:
                for key, value in config["selectorSyncSet"]['matchLabels'].items():
                    o = copy.deepcopy(config)
                    o["selectorSyncSet"]['matchLabels'].clear()
                    if 'matchExpressions' in o["selectorSyncSet"]:
                        del o["selectorSyncSet"]['matchExpressions'][:]
                    o["selectorSyncSet"]['matchLabels'].update({key:value})
                    del o["selectorSyncSet"]["matchLabelsApplyMode"]

                    # SSS objects require unique names
                    unique_sss_name = sss_name + '-' + re.sub('^.*?/', '', key)
                    add_sss_for(unique_sss_name, dirpath, environments, o["selectorSyncSet"])

            # generate new SSS per matchExpression
            if 'matchExpressions' in config["selectorSyncSet"]:
                for expression in config["selectorSyncSet"]['matchExpressions']:
                    key = expression['key']
                    o = copy.deepcopy(config)
                    if 'matchLabels' in o["selectorSyncSet"]:
                        o["selectorSyncSet"]['matchLabels'].clear()
                    del o["selectorSyncSet"]['matchExpressions'][:]
                    o["selectorSyncSet"]['matchExpressions'].append(expression)
                    del o["selectorSyncSet"]["matchLabelsApplyMode"]

                    # SSS objects require unique names
                    unique_sss_name = sss_name + '-' + re.sub('^.*?/', '', key)
                    add_sss_for(unique_sss_name, dirpath, environments, o["selectorSyncSet"])
        else:
            # Catches anyone with a rouge value
            add_sss_for(sss_name, dirpath, environments, config["selectorSyncSet"])
