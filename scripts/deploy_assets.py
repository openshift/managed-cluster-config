#!/usr/bin/python
"""Script to deploy prometheus exporters and base rules"""
# Copyright 2019 Red Hat, Inc.
# and other contributors as indicated by the @author tags.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import time
import logging
import subprocess
import sys
import os

ASSETS_FOLDER = 'deploy'
exporters = [
    {'name': 'managed-prometheus-exporter-ebs-iops-reporter', 'repo': 'git@github.com:openshift/managed-prometheus-exporter-ebs-iops-reporter.git'},
    {'name': 'managed-prometheus-exporter-stuck-ebs-vols', 'repo': 'git@github.com:openshift/managed-prometheus-exporter-stuck-ebs-vols.git'},
    {'name': 'managed-prometheus-exporter-dns', 'repo': 'git@github.com:openshift/managed-prometheus-exporter-dns.git'}
]

def call_or_fail(cmd):
    """Call subprocess.check_output and return utf-8 decoded stdout or log+exit"""
    try:
        res = subprocess.check_output(cmd, shell=True).decode('utf-8')
    except subprocess.CalledProcessError as err:
        logging.info('Command \'{}\' failed with error: {}'.format(cmd, str(err)))
        sys.exit(1)
    return res

def deploy_exporters():
    """Clone repo, build and deploy assets for each exporter"""
    for exp in exporters:

        logging.info('Cloning exporter {} from {}'.format(exp['name'], exp['repo']))
        gitCmd = "git clone {} tmp_exporters/{}".format(exp['repo'], exp['name'])
        call_or_fail(gitCmd)
        
        logging.info('Running make for {}'.format(exp['name']))
        makeCmd = "make -C tmp_exporters/{} all".format(exp['name'])
        call_or_fail(makeCmd)

        logging.info('Deploying assets for {}'.format(exp['name']))
        ocCmd = "oc apply -R -f tmp_exporters/{}/{}".format(exp['name'], ASSETS_FOLDER)
        call_or_fail(ocCmd)

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s:%(name)s:%(message)s')
    os.system('rm -fr tmp_exporters')

    logging.info('Deploying exporters assets')
    deploy_exporters()

    logging.info('Deploying main assets')
    deployCmd = "oc apply -R -f {}/".format(ASSETS_FOLDER)

    call_or_fail(deployCmd)

    logging.info('SUCCESS')
    sys.exit(0)
