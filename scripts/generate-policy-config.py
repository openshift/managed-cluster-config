#!/usr/bin/env python

import oyaml as yaml
import shutil
import os
from pathlib import Path

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
        'hs-hosted-route-monitor-operator',
        'hs-mgmt-route-monitor-api',
        'osd-cluster-admin',
        'osd-delete-backplane-script-resources',
        'osd-delete-backplane-serviceaccounts',
        'osd-backplane-managed-scripts',
        'osd-must-gather-operator',
        'osd-openshift-operators-redhat',
        'osd-pcap-collector',
        'osd-user-workload-monitoring',
        'rbac-permissions-operator-config',
        'rosa-oauth-templates',
        'rosa-console-branding',
        'rosa-console-branding-configmap',
        ]
policy_generator_config = './scripts/policy-generator-config.yaml'
config_filename = "config.yaml"
#go into each directory and copy a subset of manifests that are not SubjectPermissions or config.yaml into a /tmp dir
for directory in sorted(directories, key=str.casefold):
    # default to targeting hosted clusters
    cluster_selectors = {'hypershift.open-cluster-management.io/hosted-cluster': 'true'}
    namespace_selectors = {}
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
        if entry.name == config_filename:
            with open(entry.path) as config_file:
                config = yaml.safe_load(config_file)
                if config['deploymentMode'] == 'Policy':
                    if 'clusterSelectors' in config:
                        cluster_selectors = config['clusterSelectors']
                    if 'namespaceSelector' in config:
                        namespace_selectors = config['namespaceSelector']
    #create a dir in /resources to hold the newly generated policy-generator-config.yaml
    #copy over the generator template
    shutil.copy(policy_generator_config, temp_directory)
    with open(policy_generator_config,'r') as input_file:
        policy_template = yaml.safe_load(input_file)
    #fill in the name and path in the policy generator template
    policy_template['metadata']['name'] = 'rbac-policies'
    if Path(os.path.join(base_directory,directory, config_filename)).is_file():
        with open(os.path.join(base_directory, directory, config_filename),'r') as input_file:
            config = yaml.safe_load(input_file)
        if 'policy' in config.keys():
            if 'complianceType' in config['policy'].keys() and config['policy']['complianceType'] != '' : 
                policy_template['policyDefaults']['complianceType'] = config['policy']['complianceType'].lower()
            if 'metadataComplianceType' in config['policy'].keys() and config['policy']['metadataComplianceType'] != '' : 
                policy_template['policyDefaults']['metadataComplianceType'] = config['policy']['metadataComplianceType'].lower()
       
    for p in policy_template['policies']:
        p['name'] = policy_name
        for m in p['manifests']:
            m['path'] = path
    policy_template['policyDefaults']['placement']['clusterSelectors'] = cluster_selectors
    if not len(namespace_selectors) == 0:
        policy_template['policyDefaults']['namespaceSelector'] = namespace_selectors
    with open(os.path.join(temp_directory, "policy-generator-config.yaml"),'w+') as output_file:
        yaml.dump(policy_template, output_file)
