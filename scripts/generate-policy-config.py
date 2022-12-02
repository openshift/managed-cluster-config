#!/usr/bin/env python

import oyaml as yaml
import shutil
import os

#an array of directories you want to generate policies for. Please make sure ONLY the directories you want exist here. if there's entries here, delete it and add yours.
directory = [
        './deploy/rbac-permissions-operator-config',
        './deploy/osd-cluster-admin',
        './deploy/backplane'
        ]
policy_generator_config = './scripts/policy-generator-config.yaml'
config_filename = "config.yaml"
#go into each directory and copy a subset of manifests that are not SubjectPermissions or config.yaml into a /tmp dir
for dir in directory:
    #extract the directory name
    dir_name = os.path.basename(dir)
    temp_directory = os.path.join("/tmp", dir_name)
    #create a temporary path to stores the subset of manifests that will generate policies with
    path = os.path.join(temp_directory, "configs")
    os.makedirs(path)
    for r,d,f in os.walk(dir):
        for file in f:
            if (file.endswith('.yml') or file.endswith('.yaml') and not(file == config_filename)):
                if 'SubjectPermission' not in file:
                    shutil.copy( os.path.join(dir, file), path)
        #create a dir in /resources to hold the newly generated policy-generator-config.yaml
        #copy over the generator template
        shutil.copy(policy_generator_config, temp_directory)
        with open(policy_generator_config,'r') as input_file:
            policy_template = yaml.safe_load(input_file)
        #fill in the name and path in the policy generator template
        for p in policy_template['policies']:
            p['name'] = dir_name
            for m in p['manifests']:
                m['path'] = path
        with open(os.path.join(temp_directory, "policy-generator-config.yaml"),'w+') as output_file:
            yaml.dump(policy_template, output_file)
