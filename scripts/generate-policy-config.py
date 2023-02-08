#!/usr/bin/env python

import oyaml as yaml
import shutil
import os

base_directory = "./deploy/"
# An array of directories you want to generate policies for.
# Please make sure ONLY the directories you want exist here.
# Alphanumeric order is used to limit the risk of conflict when adding new directories in parallel. 
# Large content (such as 'rosa-oauth-templates') aren't supported with 'Apply' mode and are moved to a dedicated selector syncset
# This script doesn't walk the sub-directories.
directories = [
        'backplane',
        'backplane/cee',
        'backplane/cse',
        'backplane/csm',
        'backplane/cssre',
        'backplane/elevated-sre',
        'backplane/mobb',
        'backplane/srep',
        'backplane/tam',
        'ccs-dedicated-admins',
        'customer-registry-cas',
        'osd-cluster-admin',
        'osd-delete-backplane-script-resources',
        'osd-delete-backplane-serviceaccounts',
        'osd-backplane-managed-scripts',
        'osd-must-gather-operator',
        'osd-openshift-operators-redhat',
        'osd-pcap-collector',
        'osd-project-request-template',
        'osd-user-workload-monitoring',
        'rbac-permissions-operator-config',
        'rosa-console-branding-configmap',
        ]
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
    for p in policy_template['policies']:
        p['name'] = policy_name
        for m in p['manifests']:
            m['path'] = path
    with open(os.path.join(temp_directory, "policy-generator-config.yaml"),'w+') as output_file:
        yaml.dump(policy_template, output_file)
