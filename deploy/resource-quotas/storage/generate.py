#!/usr/bin/env python

import oyaml as yaml

import os
import sys
import argparse
import shutil

from string import Template

config_filename = "config.yaml"

if __name__ == '__main__':
    # argument parser
    parser = argparse.ArgumentParser(description="quota template generation tool", usage='%(prog)s [options]')
    parser.add_argument("--template-dir", "-t", required=True, help="Path to template directory [required]")
    parser.add_argument("--destination-dir", "-d", required=True, help="Destination folder [required]")
    parser.add_argument("--aws-storage-classes", "-a", nargs='+', required=True, help="Array of strings for AWS storage classes [required]")
    parser.add_argument("--gcp-storage-classes", "-g", nargs='+', required=True, help="Array of strings for GCP storage classes [required]")
    parser.add_argument("--quotas", "-q", nargs='+', required=True, help="Array of strings for quota counts [required]")
    arguments = parser.parse_args()

    storage_class_names = {
        "aws": arguments.aws_storage_classes,
        "gcp": arguments.gcp_storage_classes
    }

    # storage class quotas
    for provider in storage_class_names.keys():
        for sc_name in storage_class_names[provider]:

            # storage default quota
            dir_path = os.path.join(arguments.destination_dir, "{}-{}-default".format(provider, sc_name))
            if not os.path.exists(dir_path):
                os.makedirs(dir_path)
            with open(os.path.join(arguments.template_dir, "quota.yaml.tmpl"), 'r') as f:
                tmpl = Template(f.read())
                yaml_data = yaml.safe_load(tmpl.substitute({ 'CLOUD_PROVIDER': provider, 'STORAGE_CLASS_NAME': sc_name, 'STORAGE_SIZE_GB': arguments.quotas[0] }))
                with open(os.path.join(dir_path, "00-ClusterResourceQuota.yaml"), "w") as outfile:
                    yaml.dump(yaml_data, outfile)
            with open(os.path.join(arguments.template_dir, "default-config.yaml.tmpl"), 'r') as f:
                tmpl = Template(f.read())
                yaml_data = yaml.safe_load(tmpl.substitute({ 'CLOUD_PROVIDER': provider, 'STORAGE_CLASS_NAME': sc_name, 'STORAGE_SIZE_GB': arguments.quotas[0] }))
                with open(os.path.join(dir_path, config_filename), "w") as outfile:
                    yaml.dump(yaml_data, outfile)

            # storage specific quotas
            for sc_quota in arguments.quotas:
                dir_path = os.path.join(arguments.destination_dir, "{}-{}-{}gb".format(provider, sc_name, sc_quota ))
                if not os.path.exists(dir_path):
                    os.makedirs(dir_path)
                with open(os.path.join(arguments.template_dir, "quota.yaml.tmpl"), 'r') as f:
                    tmpl = Template(f.read())
                    yaml_data = yaml.safe_load(tmpl.substitute({ 'CLOUD_PROVIDER': provider, 'STORAGE_CLASS_NAME': sc_name, 'STORAGE_SIZE_GB': sc_quota }))
                    with open(os.path.join(dir_path, "00-ClusterResourceQuota.yaml"), "w") as outfile:
                        yaml.dump(yaml_data, outfile)
                with open(os.path.join(arguments.template_dir, "config.yaml.tmpl"), 'r') as f:
                    tmpl = Template(f.read())
                    yaml_data = yaml.safe_load(tmpl.substitute({ 'CLOUD_PROVIDER': provider, 'STORAGE_CLASS_NAME': sc_name, 'STORAGE_SIZE_GB': sc_quota }))
                    with open(os.path.join(dir_path, config_filename), "w") as outfile:
                        yaml.dump(yaml_data, outfile)
