#!/usr/bin/env python

import oyaml as yaml
import shutil
import os
from copy import deepcopy

base_directory = "./deploy/"
# An array of directories you want to generate policies for.
# Please make sure ONLY the directories you want exist here.
# Alphanumeric order is used to limit the risk of conflict when adding new directories in parallel.
# This script doesn't walk the sub-directories.
directories = [
        'backplane/cee',
        'backplane/cse',
        'backplane/csm',
        'backplane/lpsre',
        'backplane/mobb',
        'backplane/srep',
        'backplane/tam',
        'osd-delete-backplane-serviceaccounts',
        'osd-user-workload-monitoring',
        'rbac-permissions-operator-config',
        'ccs-dedicated-admins',
        ]
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

def get_all_yaml_files(path):
    file_paths = []
    for r,d,f in os.walk(path):
        for file in f:
            if (file.endswith('.SubjectPermission.yml') or file.endswith('.SubjectPermission.yaml') and not(file == config_filename)):
                file_paths.append(os.path.join(r,file))
        # break, so we don't recurse
        break
    file_paths = sorted(file_paths, key=str.casefold)
    return file_paths

policy_generator_config = './scripts/policy-generator-config.yaml'
config_filename = "config.yaml"
#go into each directory and copy a subset of manifests that are not SubjectPermissions or config.yaml into a /tmp dir
for directory in sorted(directories, key=str.casefold):
    #extract the directory name
    policy_name = directory.replace("/", "-")
    temp_directory = os.path.join("/tmp", policy_name + "-subjectpermissions")
    manifests = []
    #create a temporary path to stores the subset of manifests that will generate policies with
    configs_directory = os.path.join(temp_directory, "configs")
    os.makedirs(configs_directory)
    for entry in get_all_yaml_files(os.path.join(base_directory, directory)):
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
