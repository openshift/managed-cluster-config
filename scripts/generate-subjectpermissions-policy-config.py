#!/usr/bin/env python

import oyaml as yaml
import shutil
import os

base_directory = "./deploy/"
# An array of directories you want to generate policies for.
# Please make sure ONLY the directories you want exist here.
# This script doesn't walk the sub-directories.
directories = [
        'rbac-permissions-operator-config',
        'backplane/srep',
        'ccs-dedicated-admins'
        ]
policy_generator_config = './scripts/policy-generator-config.yaml'
config_filename = "config.yaml"
#go into each directory and copy a subset of manifests that are not SubjectPermissions or config.yaml into a /tmp dir
for directory in directories:
    #extract the directory name
    policy_name = directory.replace("/", "-")
    temp_directory = os.path.join("/tmp", policy_name + "-subjectpermissions")
    #create a temporary path to stores the subset of manifests that will generate policies with
    path = os.path.join(temp_directory, "configs")
    os.makedirs(path)
    for entry in os.scandir(os.path.join(base_directory, directory)):
        if not entry.is_file():
            continue
        if (entry.name.endswith('.SubjectPermission.yml') or entry.name.endswith('.SubjectPermission.yaml') and not(entry.name == config_filename)):
            shutil.copy( os.path.join(base_directory, directory, entry.name), path)
    #create a dir in /resources to hold the newly generated policy-generator-config.yaml
    #copy over the generator template
    shutil.copy(policy_generator_config, temp_directory)
    with open(policy_generator_config,'r') as input_file:
        policy_template = yaml.safe_load(input_file)
    #fill in the name and path in the policy generator template
    policy_template['metadata']['name'] = 'subjectpermission-policies'
    for p in policy_template['policies']:
        p['name'] =  policy_name + '-sp'
        for m in p['manifests']:
            m['path'] = path
    with open(os.path.join(temp_directory, "policy-generator-config.yaml"),'w+') as output_file:
        yaml.dump(policy_template, output_file)
