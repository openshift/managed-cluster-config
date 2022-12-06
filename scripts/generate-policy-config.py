#!/usr/bin/env python

import oyaml as yaml
import shutil
import os

base_directory = "./deploy/"

# Place new directories in policy-paths.yaml.
with open('./scripts/policy-paths.yaml','r') as paths_file:
    # Please make sure ONLY the directories you want exist here.
    # This script doesn't walk the sub-directories.
    paths_yaml = yaml.safe_load(paths_file)
    directories = paths_yaml['policies']['paths']
    policies_namespace = paths_yaml['policies']['namespace']
    # Array of policy directories targeting limited-support clusters
    limited_support = paths_yaml['limited-support-policies']['paths']
    ls_namespace = paths_yaml['limited-support-policies']['namespace']

policy_generator_config = './scripts/policy-generator-config.yaml'
config_filename = "config.yaml"

#go into each directory and copy a subset of manifests that are not SubjectPermissions or config.yaml into a /tmp dir
for directory in sorted(directories, key=str.casefold):
    #extract the directory name
    policy_name = directory.replace("/", "-")
    temp_directory = os.path.join("/tmp", policy_name)
    #create a temporary path to stores the subset of manifests that will generate policies with
    path = os.path.join(temp_directory, "configs")
    os.makedirs(path)
    for entry in os.scandir(os.path.join(base_directory, directory)):
        if not entry.is_file():
            continue
        if (entry.name.endswith('.yml') or entry.name.endswith('.yaml') and not(entry.name == config_filename)):
            if 'SubjectPermission' not in entry.name:
                shutil.copy( os.path.join(base_directory, directory, entry.name), path)
    #create a dir in /resources to hold the newly generated policy-generator-config.yaml
    #copy over the generator template
    shutil.copy(policy_generator_config, temp_directory)
    with open(policy_generator_config,'r') as input_file:
        policy_template = yaml.safe_load(input_file)
    #fill in the name and path in the policy generator template
    policy_template['metadata']['name'] = 'rbac-policies'
    policy_template['policyDefaults']['namespace'] = policies_namespace

    # Add limited support cluster selector and namespace
    if directory in limited_support:
        policy_template['policyDefaults']['placement']['clusterSelectors']['api.openshift.com/limited-support'] = 'true'
        policy_template['policyDefaults']['namespace'] = ls_namespace

    for p in policy_template['policies']:
        p['name'] = policy_name
        for m in p['manifests']:
            m['path'] = path
    with open(os.path.join(temp_directory, "policy-generator-config.yaml"),'w+') as output_file:
        yaml.dump(policy_template, output_file)
