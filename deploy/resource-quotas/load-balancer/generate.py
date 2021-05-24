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
    parser.add_argument("--quotas", "-q", nargs='+', required=True, help="Array of strings for quota counts [required]")
    arguments = parser.parse_args()

    # load balancer default quota
    dir_path = os.path.join(arguments.destination_dir, "lb-default")
    if not os.path.exists(dir_path):
        os.makedirs(dir_path)
    with open(os.path.join(arguments.template_dir, "quota.yaml.tmpl"), 'r') as f:
        tmpl = Template(f.read())
        yaml_data = yaml.safe_load(tmpl.substitute({ 'LB_COUNT': arguments.quotas[0] }))
        with open(os.path.join(dir_path, "00-ClusterResourceQuota.yaml"), "w") as outfile:
            yaml.dump(yaml_data, outfile)
    with open(os.path.join(arguments.template_dir, "default-config.yaml.tmpl"), 'r') as f:
        tmpl = Template(f.read())
        yaml_data = yaml.safe_load(tmpl.substitute({ 'LB_COUNT': arguments.quotas[0] }))
        with open(os.path.join(dir_path, config_filename), "w") as outfile:
            yaml.dump(yaml_data, outfile)

    # load balancer specific quotas
    for lb_quota in arguments.quotas:
        dir_path = os.path.join(arguments.destination_dir, "lb-{}".format(lb_quota))
        if not os.path.exists(dir_path):
            os.makedirs(dir_path)
        with open(os.path.join(arguments.template_dir, "quota.yaml.tmpl"), 'r') as f:
            tmpl = Template(f.read())
            yaml_data = yaml.safe_load(tmpl.substitute({ 'LB_COUNT': lb_quota }))
            with open(os.path.join(dir_path, "00-ClusterResourceQuota.yaml"), "w") as outfile:
                yaml.dump(yaml_data, outfile)
        with open(os.path.join(arguments.template_dir, "config.yaml.tmpl"), 'r') as f:
            tmpl = Template(f.read())
            yaml_data = yaml.safe_load(tmpl.substitute({ 'LB_COUNT': lb_quota }))
            with open(os.path.join(dir_path, config_filename), "w") as outfile:
                yaml.dump(yaml_data, outfile)
