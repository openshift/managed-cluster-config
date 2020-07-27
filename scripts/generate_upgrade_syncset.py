#!/bin/env python

import argparse
import datetime
import json
import logging
import os
import re
import subprocess
import sys
import ruamel.yaml as yaml
from ruamel.yaml.scalarstring import DoubleQuotedScalarString as dq

CS = yaml.comments.CommentedSeq
CM = yaml.comments.CommentedMap

# Script to generate the cluster list
CLUSTER_LIST_EXEC = 'get-cluster-list.sh'
# SyncSet CR constants
SS_API_VERSION = 'hive.openshift.io/v1'
SS_NAME = 'osd-upgrade-config'
# UpgradeConfig CR constants
UC_NAME = 'osd-upgrade-config'
UC_NAMESPACE = 'openshift-managed-upgrade-operator'
UC_API_VERSION = 'upgrade.managed.openshift.io/v1alpha1'
UC_PDB_DRAIN_TIMEOUT = 60
UC_FORCE = False

def get_cluster_info(cluster_ids, groups, subgroup, environment):
    """
    Returns a list of clusters matching the supplied group and subgroup
    :param group: Cluster group
    :param subgroup: Cluster subgroup
    :return: list of tuple pairs of cluster ID and cluster name
    """

    cluster_id_to_name = dict()

    if cluster_ids is not None:
        for cluster_id in cluster_ids:
            try:
                cluster_name = get_cluster_name_for_id(cluster_id, environment)
                cluster_id_to_name[cluster_id] = cluster_name
            except Exception as err:
                logging.error('Unable to determine cluster name for cluster ID \'{}\': {}'.format(cluster_id, str(err)))
                sys.exit(1)

    if groups is not None:
        for g in groups:
            try:
                # pout = subprocess.check_output(['cat', '/home/mbargenq/scratch/' + g + '.txt']).decode('utf-8')
                pout = subprocess.check_output([CLUSTER_LIST_EXEC, g, subgroup]).decode('utf-8')
                output_as_dict = json.loads(pout)

                if 'items' not in output_as_dict:
                    logging.error('Unexpected cluster info returned, unable to determine id/name')
                    sys.exit(1)

                cluster_items = output_as_dict['items']
                for cluster in cluster_items:
                    cluster_id_to_name[cluster['id']] = cluster['longName']

            except OSError as err:
                logging.info('Command \'{}\' failed with error: {}'.format(CLUSTER_LIST_EXEC, str(err)))
                sys.exit(1)
            except subprocess.CalledProcessError as err:
                logging.info('Command \'{}\' failed with error: {}'.format(CLUSTER_LIST_EXEC, str(err)))
                sys.exit(1)
            except ValueError as err:
                logging.info(
                    'Output of command \'{}\' failed to parse with error: {}'.format(CLUSTER_LIST_EXEC, str(err)))
                sys.exit(1)

    return cluster_id_to_name


def get_cluster_name_for_id(cluster_id, environment):
    """
    Determines the clusterdeployment name associated with the supplied clusterid
    :param cluster_id: cluster-id of cluster
    :return: clusterdeployment name associated with cluster ID
    """
    cluster_ns = 'uhc-{}-{}'.format(environment, cluster_id)
    try:
        # pout = subprocess.check_output(['cat', '/home/mbargenq/scratch/cluster.txt']).decode(
        #     'utf-8')
        pout = subprocess.check_output(['oc', 'get', 'clusterdeployment', '-n', cluster_ns, '-o', 'json']).decode(
            'utf-8')
        output_as_dict = json.loads(pout)
        if 'items' not in output_as_dict:
            raise Exception('fetching clusterdeployment returned invalid response')

        cd = output_as_dict['items']
        if len(cd) == 0:
            raise Exception('clusterdeployment not found')

        return cd[0]['metadata']['name']

    except Exception as err:
        raise err


def generate_upgradeconfig(start_time, version, channel):
    """
    Generates the UpgradeConfig CR in python dict form
    :param version: version to upgrade to
    :param channel: channel for upgrade
    :param force: force upgrade
    :return: dict representation of upgradeconfig CR
    """
    uc = {
        'apiVersion': UC_API_VERSION,
        'kind': 'UpgradeConfig',
        'metadata': {
            'name': UC_NAME,
            'namespace': UC_NAMESPACE,
        },
        'spec': {
            'type': dq('OSD'),
            'upgradeAt': dq(start_time),
            'proceed': True,
            'PDBForceDrainTimeout': UC_PDB_DRAIN_TIMEOUT,
            'desired': {
                'version': dq(version),
                'channel': dq(channel),
                'force': UC_FORCE,
            }
        }
    }
    return uc


def generate_syncset(upgradeconfig, cluster_id, cluster_name='', environment='production'):
    """
    Generates the SelectorSyncSet
    :param upgradeconfig: UpgradeConfig CR as dict
    :param cluster_id: Cluster ID to target
    :param cluster_name: Cluster name to target
    :return: SelectorSyncSet as dict
    """

    # generate the namespace for the SyncSet in hive format
    # uhc-<environment>-<clusterID>
    ss_namespace = 'uhc-{}-{}'.format(environment, cluster_id)

    data = CM()
    data['apiVersion'] = SS_API_VERSION
    data['kind'] = 'SyncSet'
    data['metadata'] = {
        'labels': {
            'api.openshift.com/id': cluster_id,
            'api.openshift.com/name': cluster_name,
        },
        'name': SS_NAME,
        'namespace': ss_namespace,
    }

    data['spec'] = {
        'clusterDeploymentRefs': [
            {
                'name': dq(cluster_name),
            }
        ],
        'resourceApplyMode': 'Upsert',
        'resources': [
            upgradeconfig
        ],
    }

    yaml.preserve_quotes = True
    yaml.dump(data, sys.stdout, Dumper=yaml.RoundTripDumper)


def init_logging():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s:%(name)s:%(message)s')


def generate_syncsets(clusters, start_time, version, channel, environment='production'):
    outer = CM()
    outer['apiVersion'] = 'v1'
    outer['kind'] = 'List'

    items = CS()
    for cluster_id, cluster_name in clusters.items():
        uc = generate_upgradeconfig(start_time, version, channel)
        ss_namespace = 'uhc-{}-{}'.format(environment, cluster_id)
        data = CM()
        data['apiVersion'] = SS_API_VERSION
        data['kind'] = 'SyncSet'
        data['metadata'] = {
            'labels': {
                'api.openshift.com/id': cluster_id,
                'api.openshift.com/name': cluster_name,
            },
            'name': SS_NAME,
            'namespace': ss_namespace,
        }

        data['spec'] = {
            'clusterDeploymentRefs': [
                {
                    'name': dq(cluster_name),
                }
            ],
            'resourceApplyMode': 'Upsert',
            'resources': [
                uc
            ],
        }
        items.append(data)

    outer['items'] = items

    yaml.preserve_quotes = True
    yaml.dump(outer, sys.stdout, Dumper=yaml.RoundTripDumper)


def init_argparse():
    """
    Initialises the command-line argument parser
    :return: parser instance
    """
    parser = argparse.ArgumentParser(description='UpgradeConfig SelectorSyncSet generator',
                                     usage='%(prog)s [options]')

    parser.add_argument('--subgroup', required=False, choices=['all', 'prod', 'nonprod'], default='all',
                        help='Sub-cluster-group to target (default=all)')
    parser.add_argument('--start-time', required=False, type=valid_date,
                        help='Timestamp at which upgrade should commence (eg. 2020-01-25T00:00:00Z)')
    parser.add_argument('--version', required=True, type=valid_version, help='Target upgrade version [required]')
    parser.add_argument('--channel', required=True, help='Target upgrade channel [required]')
    parser.add_argument('--force', '-f', required=False, default=False, help='Force upgrade [optional, default false]')
    parser.add_argument('--environment', '-e', required=False, choices=['production', 'staging', 'integration'],
                        default='production', help='Hive environment [optional, default production]')

    cluster_group = parser.add_argument_group()
    cluster_group.add_argument('--cluster-id', '-c', required=False, action='append', help='Cluster ID to target')
    cluster_group.add_argument('--group', '-g', required=False, action='append',
                               choices=['sd', 'sre', 'cicd', 'internal', 'snowflake', 'external'],
                               help='Cluster group to target')

    return parser


def valid_version(v):
    """
    Verify the supplied version adheres to formatting conventions
    :param v: version to verify
    :return: the unmodified version if it parses successfully
    :raises ArgumentError if version is invalid
    """
    p = re.compile('^4\\.[0-9]+\\.[0-9]+')
    result = p.match(v)
    if not result:
        raise argparse.ArgumentError('Version must be in format 4.X.Y, eg. 4.3.25')
    return v


def valid_date(d):
    """
    Verify the supplied timestamp adheres to formatting conventions
    :param d: timestamp to verify
    :return: the unmodified timestamp if it parses successfully
    :raises ArgumentError if timestamp is invalid
    """
    try:
        datetime.datetime.strptime(d, '%Y-%m-%dT%H:%M:%SZ')
    except ValueError:
        raise argparse.ArgumentError('Time must be in format YYYY-MM-DDTHH:MM:SSZ, eg. 2020-01-25T00:00:00Z')
    return d


def check_environment():
    """
    Checks the system environment for the presence of the cluster-list fetcher
    :return: bool indicating success
    """
    for path in os.environ["PATH"].split(os.pathsep):
        exe_file = os.path.join(path, CLUSTER_LIST_EXEC)
        if os.path.isfile(exe_file) and os.access(exe_file, os.X_OK):
            return True

    logging.info("Missing required executable {}, ensure it is in PATH.".format(CLUSTER_LIST_EXEC))
    return False


if __name__ == '__main__':
    # program initialization
    init_logging()
    parser = init_argparse()
    args = parser.parse_args()

    # # validate the dependent program(s) is valid
    if not check_environment():
        sys.exit(1)

    # fetch the list of candidate clusters
    clusters = get_cluster_info(args.cluster_id, args.group, args.subgroup, args.environment)

    upgrade_config = generate_upgradeconfig(args.start_time, args.version, args.channel)
    generate_syncsets(clusters, args.start_time, args.version, args.channel, args.environment)
