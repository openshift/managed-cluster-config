#!/usr/bin/env python
import oyaml as yaml
import shutil
import os
import subprocess
import sys
from pathlib import Path
import argparse
import re
from copy import deepcopy

config_filename = "config.yaml"
config_directory = "/tmp/*/"
config_name = "policy-generator-config.yaml"
policy_generator_config = './scripts/policy-generator-config.yaml'
cluster_selectors = {'hypershift.open-cluster-management.io/hosted-cluster': 'true'}
namespace_selectors = {}

rolebinding = \
{'apiVersion': 'rbac.authorization.k8s.io/v1',
'kind': 'RoleBinding',
'metadata': {'name': 'placeholder'},
'roleRef': {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'ClusterRole', 'name': 'placeholder'},
'subjects': [{'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'placeholder', 'name': 'placeholder'}]}

clusterrolebinding = \
{'apiVersion': 'rbac.authorization.k8s.io/v1',
'kind': 'ClusterRoleBinding',
'metadata': {'name': 'placeholder'},
'roleRef': {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'ClusterRole', 'name': 'placeholder'},
'subjects': [{'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'placeholder', 'name': 'placeholder'}]}

# namespace in SubjectPermission is regex, but namespace selector doesn't support regex
# for most cases using the string match should be enough
# example "(^kube$|^kube-.*|^openshift$|^openshift-.*|^default$|^redhat-.*)"

def regex_to_strings(regex):
    regex = regex.replace("(","")
    regex = regex.replace(")","")
    strings = regex.split("|")
    for i in range(len(strings)):
        strings[i] = strings[i].replace("^","")
        strings[i] = strings[i].replace("$","")
        strings[i] = strings[i].replace(".*","*")
    return strings

def get_yaml(filename):
    with open(filename,'r') as input_file:
        return yaml.safe_load(input_file)


def generate_policy_config(directory):
    cluster_selectors = {'hypershift.open-cluster-management.io/hosted-cluster': 'true'}
    file_paths_sp = []
    namespace_selectors = {}
    #extract the directory name
    short_dir = re.sub('deploy/', '', dirpath)
    policy_name = short_dir.replace("/", "-")
    temp_directory = os.path.join("/tmp", policy_name)
    #create a temporary path to stores the subset of manifests that will generate policies with
    path = os.path.join(temp_directory, "configs")
    os.makedirs(path)
    #walk through the files in the directory, if the file's kind is SubjectPermission, call generate_sp. If it's any other kind, call generate_regular
    for entry in os.scandir(directory):
        if not entry.is_file():
            #don't scan subdirectory
            continue
        if entry.name == config_filename:
            with open(entry.path) as config_file:
                config = yaml.safe_load(config_file)
                if config['deploymentMode'] == 'Policy':
                    if 'clusterSelectors' in config:
                        cluster_selectors = config['clusterSelectors']
                    if 'namespaceSelector' in config:
                        namespace_selectors = config['namespaceSelector']
        if (entry.name.endswith('.yml') or entry.name.endswith('.yaml') and not(entry.name == config_filename)):
            if 'SubjectPermission' not in entry.name:
                #if the yaml is not SubjectPermission, copy the files over to the /tmp directory 
                shutil.copy( os.path.join(directory, entry.name), path)
                non_sp_config(directory, temp_directory, policy_name, path)
            else:
                temp_directory_sp = os.path.join("/tmp", policy_name + "-subjectpermissions")
                configs_directory = os.path.join(temp_directory_sp, "configs")
                if not os.path.exists(configs_directory) :
                    os.makedirs(configs_directory)
                file_paths_sp.append(os.path.join(directory, entry.name))
                file_paths_sp = sorted(file_paths_sp, key=str.casefold)
                sp_config(file_paths_sp, temp_directory_sp, policy_name, configs_directory)


def non_sp_config(directory, temp_directory, policy_name, path):
    cluster_selectors = {'hypershift.open-cluster-management.io/hosted-cluster': 'true'}
    namespace_selectors = {}
    shutil.copy(policy_generator_config, temp_directory)
    with open(policy_generator_config,'r') as input_file:
        policy_template = yaml.safe_load(input_file)
    #fill in the name and path in the policy generator template
    policy_template['metadata']['name'] = 'rbac-policies'
    if Path(os.path.join(directory, config_filename)).is_file():
        with open(os.path.join(directory, config_filename),'r') as input_file:
            config = yaml.safe_load(input_file)
        if 'policy' in config.keys():
            if 'complianceType' in config['policy'].keys() and config['policy']['complianceType'] != '' :
                policy_template['policyDefaults']['complianceType'] = config['policy']['complianceType'].lower()
            if 'metadataComplianceType' in config['policy'].keys() and config['policy']['metadataComplianceType'] != '' :
                policy_template['policyDefaults']['metadataComplianceType'] = config['policy']['metadataComplianceType'].lower()
            if 'clusterSelectors' in config['policy'].keys() and config['policy']['clusterSelectors'] != '':
                        cluster_selectors = config['policy']['clusterSelectors']
            if 'namespaceSelector' in config['policy'].keys() and config['policy']['namespaceSelector'] != '':
                        namespace_selectors = config['policy']['namespaceSelector']

    for p in policy_template['policies']:
        p['name'] = policy_name
        for m in p['manifests']:
            m['path'] = path
    policy_template['policyDefaults']['placement']['clusterSelectors'] = cluster_selectors
    if not len(namespace_selectors) == 0:
        policy_template['policyDefaults']['namespaceSelector'] = namespace_selectors
    with open(os.path.join(temp_directory, "policy-generator-config.yaml"),'w+') as output_file:
        yaml.dump(policy_template, output_file)

    return


def sp_config(file_paths_sp, temp_directory, policy_name, configs_directory):
    manifests = []
    for entry in file_paths_sp:
        with open(entry,'r') as input_file:
            sp_obj = yaml.safe_load(input_file)
            rolebinding_name_prefix = sp_obj["metadata"]["name"]
            # for each clusterpermission, create a non-namespaced clusterrolebinding and a manifest item
            if "clusterPermissions" in sp_obj["spec"]:
                for i in range(len(sp_obj["spec"]["clusterPermissions"])):
                    cluster_permission = sp_obj["spec"]["clusterPermissions"][i]
                    clusterrolebinding_name = rolebinding_name_prefix + "-c" + str(i)
                    clusterrolebinding["metadata"]["name"] = clusterrolebinding_name
                    clusterrolebinding["roleRef"]["name"] = cluster_permission
                    clusterrolebinding["subjects"][0]["kind"] = sp_obj["spec"]["subjectKind"]
                    clusterrolebinding["subjects"][0]["name"] = sp_obj["spec"]["subjectName"]
                    # dump a clusterrolebinding yaml file
                    crb_filename = os.path.join(configs_directory, clusterrolebinding_name + ".yaml")
                    with open(crb_filename,'w+') as output_file:
                        yaml.dump(clusterrolebinding, output_file)
                    # create a manifest item for this clusterrolebinding
                    manifest = {}
                    manifest["path"] = crb_filename
                    manifests.append(manifest)

            # for each permission, create a rolebinding yaml file and a manifest item
            if "permissions" in sp_obj["spec"]:
                for i in range(len(sp_obj["spec"]["permissions"])):
                    allow_ns = ''
                    deny_ns = ''
                    permission = sp_obj["spec"]["permissions"][i]
                    rolebinding_name = rolebinding_name_prefix + "-" + str(i)
                    rolebinding["metadata"]["name"] = rolebinding_name
                    rolebinding["roleRef"]["name"] = permission["clusterRoleName"]
                    rolebinding["subjects"][0]["kind"] = sp_obj["spec"]["subjectKind"]
                    rolebinding["subjects"][0]["name"] = sp_obj["spec"]["subjectName"]
                    if "namespacesAllowedRegex" in permission:
                        allow_ns = regex_to_strings(permission["namespacesAllowedRegex"])
                    if "namespacesDeniedRegex" in permission:
                        deny_ns = regex_to_strings(permission["namespacesDeniedRegex"])
                    # dump a rolebinding yaml file
                    rb_filename = os.path.join(configs_directory, rolebinding_name + ".yaml")
                    with open(rb_filename,'w+') as output_file:
                        yaml.dump(rolebinding, output_file)
                    # create a manifest item for this rolebinding with namespace selector
                    manifest = {}
                    manifest["path"] = rb_filename
                    manifest["namespaceSelector"] = {}
                    if allow_ns:
                        manifest["namespaceSelector"]["include"] = deepcopy(allow_ns)
                    if deny_ns:
                        manifest["namespaceSelector"]["exclude"] = deepcopy(deny_ns)
                    manifests.append(manifest)
        #create a dir in /resources to hold the newly generated policy-generator-config.yaml
        #copy over the generator template
        policy_generator_config = './scripts/policy-generator-config.yaml'
        shutil.copy(policy_generator_config, temp_directory)
        with open(policy_generator_config,'r') as input_file:
            policy_template = yaml.safe_load(input_file)
        #fill in the name and path in the policy generator template
        policy_template['metadata']['name'] = 'subjectpermission-policies'
        policy_template['policyDefaults']['consolidateManifests'] = False
        for p in policy_template['policies']:
            p['name'] =  policy_name + '-sp'
            p['manifests'] = manifests
        with open(os.path.join(temp_directory, "policy-generator-config.yaml"),'w+') as output_file:
            yaml.dump(policy_template, output_file)
    return


#generate the policies using the generated configs
def generate_policy():
    subprocess.run("./scripts/generate-policy.sh")
    return

def add_resource_to_deploy(directory):
    #copy the files to generated_deploy
    dir = re.sub('deploy/', '', directory)
    new_directory = os.path.join("./generated_deploy", dir)
    shutil.copytree(directory, new_directory, dirs_exist_ok=True)
    return


if __name__ == '__main__':
    #Argument parser
    parser = argparse.ArgumentParser(description="sync resource generation tool", usage='%(prog)s [options]')
    parser.add_argument("--yaml-directory", "-y", required=True, help="Path to folder containing yaml files [required]")
    parser.add_argument("--destination", "-d", required=True, help="Destination directory for template files [required]")
    parser.add_argument("--repo-name", "-r", required=True, help="Name of the repository [required]")
    arguments = parser.parse_args()


    dirpaths = []
    for (dirpath, dirnames, filenames) in os.walk(arguments.yaml_directory) :
        if filenames:
            dirpaths.append(dirpath)


    for dirpath in sorted(dirpaths, key=str.casefold):
        # load config if it exists
        config = {}
        path_config = os.path.join(dirpath, config_filename)
        if os.path.exists(path_config):
            #read config.yaml
            config = get_yaml(path_config)

        deploymentMode = "SelectorSyncSet"
        if "deploymentMode" in config:
            deploymentMode = config["deploymentMode"]

        if deploymentMode == "SelectorSyncSet" or deploymentMode == "Direct":
            #if deploymentMode has SSS, copy that dir to /generated_deploy
            add_resource_to_deploy(dirpath)
            if "policy" in config:
                if "policy" in config:
                    generate_policy_config(dirpath)

        if deploymentMode == "Policy":
            #if deploymentMode is Policy, generate the policy then safe to /generated_deploy/acm_policies
                generate_policy_config(dirpath)


    generate_policy()
