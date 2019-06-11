#!/usr/bin/env python

# logic for sorted output: https://gist.github.com/oglops/c70fb69eef42d40bed06

try:
        # for python newer than 2.7
    from collections import OrderedDict
except ImportError:
        # use backport from pypi
    from ordereddict import OrderedDict

import yaml

try:
    from yaml import CLoader as Loader, CDumper as Dumper
except ImportError:
    from yaml import Loader, Dumper
from yaml.representer import SafeRepresenter
_mapping_tag = yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG

import os
import sys
import argparse
import copy

def dict_representer(dumper, data):
    return dumper.represent_dict(data.iteritems())

def dict_constructor(loader, node):
    return OrderedDict(loader.construct_pairs(node))


def get_yaml_all(filename):
    with open(filename,'r') as input_file:
        return list(yaml.load_all(input_file))

def get_yaml(filename):
    with open(filename,'r') as input_file:
        return yaml.safe_load(input_file)

def get_all_yaml_files(path):
    file_paths = []
    for r,d,f in os.walk(path):
        for file in f:
            if file.endswith('.yml') or file.endswith('.yaml'):
                file_paths.append(os.path.join(r,file))
        # break, so we don't recurse
        break
    file_paths = sorted(file_paths)
    return file_paths

def get_all_yaml_obj(file_paths):
    yaml_objs = []
    for file in file_paths:
        objects = get_yaml_all(file)
        for obj in objects:
            yaml_objs.append(obj)
    yaml_objs = sorted(yaml_objs)
    return yaml_objs

def process_yamls(name, directory, obj):
    o = copy.deepcopy(obj)
    # Get all yaml files as array of yaml objects
    yamls = get_all_yaml_obj(get_all_yaml_files(directory))
    if len(yamls) == 0:
        return

    yamls = sorted(yamls)
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
    # append object to the template's objects
    template_data['objects'].append(o)


if __name__ == '__main__':
    #Argument parser
    parser = argparse.ArgumentParser(description="selectorsyncset generation tool", usage='%(prog)s [options]')
    parser.add_argument("--template-dir", "-t", required=True, help="Path to template directory [required]")
    parser.add_argument("--yaml-directory", "-y", required=True, help="Path to folder containing yaml files [required]")
    parser.add_argument("--destination", "-d", required=True, help="Destination for selectorsynceset file [required]")
    parser.add_argument("--repo-name", "-r", required=True, help="Name of the repository [required]")
    arguments = parser.parse_args()

    # Get the template data
    template_data = get_yaml(os.path.join(arguments.template_dir, "template.yaml"))
    selectorsyncset_data = get_yaml(os.path.join(arguments.template_dir, "selectorsyncset.yaml"))

    # The templates and script are shared across repos (copy & paste).
    # Set the REPO_NAME parameter.
    for p in template_data['parameters']:
        if p['name'] == 'REPO_NAME':
            p['value'] = arguments.repo_name

    # for each subdir of yaml_directory append 'object' to template
    for (dirpath, dirnames, filenames) in os.walk(arguments.yaml_directory):
        if filenames:
            sss_name = dirpath.replace('/','-')
            if sss_name == arguments.yaml_directory:
                # files in the root dir, use repo-name for SSS name
                sss_name = arguments.repo_name
            else:
                # SSS name is based on dirpath which has the root path prefixed.. remove that prefix
                sss_name = sss_name[(len(arguments.yaml_directory) + 1):]
            process_yamls(sss_name, dirpath, selectorsyncset_data)

    # write template file ordering by keys
    Dumper.add_representer(OrderedDict, dict_representer)
    Loader.add_constructor(_mapping_tag, dict_constructor)

    Dumper.add_representer(str,
                        SafeRepresenter.represent_str)

    Dumper.add_representer(unicode,
                        SafeRepresenter.represent_unicode)

    with open(arguments.destination,'w') as outfile:
        yaml.dump(template_data, outfile, Dumper=Dumper, default_flow_style=False)
