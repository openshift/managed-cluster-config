#!/usr/bin/python
import os
import sys
import yaml 
import argparse

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
    file_paths = sorted(file_paths)
    return file_paths

def get_all_yaml_obj(file_paths):
    yaml_objs = []
    for file in file_paths:
        objects = get_yaml_all(file)
        for obj in objects:
            yaml_objs.append(obj)
    return yaml_objs


if __name__ == '__main__':
    #Argument parser
    parser = argparse.ArgumentParser(description="selectorsyncset generation tool", usage='%(prog)s [options]')
    parser.add_argument("--template-path", "-t", required=True, help="Path to template file [required]")
    parser.add_argument("--yaml-directory", "-y", required=True, help="Path to folder containing yaml files [required]")
    parser.add_argument("--destination", "-d", required=True, help="Destination for selectorsynceset file [required]")
    parser.add_argument("--git-hash", "-c", required=True, help="Commit hash of commit used [required]")
    arguments = parser.parse_args()

    # Get all yaml files as array of yaml objecys
    yamls = get_all_yaml_obj(get_all_yaml_files(arguments.yaml_directory))
    # Get the template data
    template_data = get_yaml(arguments.template_path)
    # Configure template
    if not 'labels' in template_data['metadata']:
        template_data['metadata']['labels'] = {}
    # create labels
    template_data['metadata']['labels']['managed.openshift.io/osd'] = True
    template_data['metadata']['labels']['managed.openshift.io/gitHash'] = arguments.git_hash
    
    # create resources
    template_data['spec']['resources'] = yamls
    
    # write selectorsyncset file
    with open(arguments.destination,'w') as outfile:
        yaml.dump(template_data,outfile)