#!/bin/env python

import csv
import uuid
import argparse
import datetime
import json
import logging
import os
import re
import subprocess

# SyncSet CR constants
SYNCSET_API_VERSION = 'hive.openshift.io/v1'
SYNCSET_NAME = 'osd-upgrade-config'

# UpgradeConfig CR constants
# The name of the UpgradeConfig CR distributed by the SyncSet
UPGRADECONFIG_NAME = 'osd-upgrade-config'
# The namespace the UpgradeConfig CR will be distributed to
UPGRADECONFIG_NAMESPACE = 'openshift-managed-upgrade-operator'
# API version of the UpgradeConfig CR
UPGRADECONFIG_API_VERSION = 'upgrade.managed.openshift.io/v1alpha1'
# PodDisruptionBudget timeout default (minutes) for the UpgradeConfig
UPGRADECONFIG_PODDISRUPTIONBUDGET_TIMEOUT_DEFAULT = 60

# Leading identifier of the 'catch-all' group of clusters as recorded in the spreadsheet
CATCHALL_CLUSTER_ID = 'everybody'

# Cluster naming conventions we will ignore entirely
CLUSTER_IGNORE_PREFIXES = ['osde2e-']


def init_logging():
    logging.basicConfig(level=logging.DEBUG, format='%(asctime)s %(levelname)s:%(name)s:%(message)s')


def init_argparse():
    """
    Initialises the command-line argument parser
    :return: parser instance
    """
    parser = argparse.ArgumentParser(description='UpgradeConfig SyncSet-bundle generator')
    parser.add_argument('--schedule_file', '-f', required=True, type=valid_file,
                        help='Exported schedule CSV file [required]')
    parser.add_argument('--output_file', '-o', required=True,
                        help='Output syncset bundle file [required]')

    cluster_group = parser.add_argument_group()
    cluster_group.add_argument('--cluster-id', '-c', required=False, action='append', help='Cluster ID to filter')

    return parser


def valid_version(v):
    """
    Verify the supplied version adheres to formatting conventions
    :param v: version to verify
    :return: true if version is valid, false otherwise
    """
    p = re.compile('^4\\.[0-9]+\\.[0-9]+')
    result = p.match(v)
    if not result:
        return False
    return True


def valid_date(d):
    """
    Verify the supplied timestamp adheres to formatting conventions
    :param d: timestamp to verify
    :return: true if timestamp is valid
    """
    try:
        datetime.datetime.strptime(d, '%Y-%m-%dT%H:%M:%SZ')
    except ValueError:
        return False
    return True


def valid_file(f):
    """
    Verify that the supplied file exists
    :param f:
    :return:
    """
    if not os.path.isfile(f):
        raise argparse.ArgumentError('File does not exist.')
    return f


def generate_upgradeconfig(start_time, version, channel):
    """
    Generates the UpgradeConfig CR in python dict form
    :param start_time: time the upgrade should commence
    :param version: version to upgrade to
    :param channel: channel for upgrade
    """
    uc = {
        'apiVersion': UPGRADECONFIG_API_VERSION,
        'kind': 'UpgradeConfig',
        'metadata': {
            'name': UPGRADECONFIG_NAME,
            'namespace': UPGRADECONFIG_NAMESPACE,
        },
        'spec': {
            'type': 'OSD',
            'upgradeAt': start_time,
            'PDBForceDrainTimeout': UPGRADECONFIG_PODDISRUPTIONBUDGET_TIMEOUT_DEFAULT,
            'desired': {
                'version': version,
                'channel': channel,
            }
        }
    }
    return uc


def get_all_clusterdeployments():
    """
    Returns the clusterdeployments running on the currently-connected Hive
    :return: clusterdeployment json blob
    """
    try:
        pout = subprocess.check_output(['oc', 'get', 'clusterdeployments', '--all-namespaces', '-o', 'json']).decode(
            'utf-8')
        output_as_dict = json.loads(pout)
        if 'items' not in output_as_dict:
            raise Exception('fetching clusterdeployments returned invalid response')

        cd = output_as_dict['items']
        if len(cd) == 0:
            raise Exception('no clusterdeployments found')

        return cd

    except Exception as err:
        raise err


def parse_schedule_file(f):
    """
    Parses the cluster upgrade schedules out of the schedule CSV
    :param f: path to the schedule CSV file
    :return:
    """
    clusters = {}
    with open(f, mode='r') as csvf:
        csv_reader = csv.reader(csvf, delimiter=',', quotechar='"')
        lineno = 0
        for row in csv_reader:
            lineno += 1

            cluster_ext_id = row[2]

            if row[0].lower().startswith(CATCHALL_CLUSTER_ID):
                # Special case of 'everybody' line
                cluster_ext_id = CATCHALL_CLUSTER_ID
            else:
                # just validate this looks like a proper cluster line
                try:
                    uuid.UUID(cluster_ext_id)
                except ValueError as err:
                    logging.warn('Ignoring schedule line {}, unable to detect external ID.'.format(lineno))
                    continue

            cluster_schedule = {
                'cluster_id': row[1],
                'external_id': row[2],
                'name': row[3],
                'channel': row[8],
                'version': row[9],
                'upgrade_at': row[10]
            }
            clusters[cluster_ext_id] = cluster_schedule

    # if we didn't find a 'catch all' schedule, notify:
    if CATCHALL_CLUSTER_ID not in clusters:
        logging.warn('No "everybody else" schedule found - some clusters may be ignored.')

    return clusters


def generate_syncset_bundle(cluster_deployments, cluster_schedules, cluster_ids):
    syncset_bundle = {
        'apiVersion': 'v1',
        'kind': 'List'
    }

    cluster_syncsets = []

    # look through all clusterdeployments
    for cd in cluster_deployments:
        namespace = cd['metadata']['namespace']
        cluster_id = cd['metadata']['labels']['api.openshift.com/id']
        external_id = cd['spec']['clusterMetadata']['clusterID']
        full_cluster_name = cd['metadata']['labels']['api.openshift.com/name']
        trunc_cluster_name = cd['spec']['clusterName']
        managed = cd['metadata']['labels']['api.openshift.com/managed']

        # is this a cluster-id in the allow-list?
        if cluster_ids and cluster_id not in cluster_ids:
            logging.info("Skipping cluster '{}' ({}) as it is not in the allow-list".format(full_cluster_name, cluster_id))
            continue

        # is this cluster in the ignore list?
        if full_cluster_name.startswith(tuple(CLUSTER_IGNORE_PREFIXES)):
            logging.info("Skipping cluster '{}' ({}) as it is in the ignore list.".format(full_cluster_name, cluster_id))
            continue

        # is this a cluster we manage?
        if managed != "true":
            logging.warn("Ignoring cluster '{}' ({}) as it is not set as managed".format(full_cluster_name, cluster_id))
            continue

        # build the syncset base
        cluster_syncset = {
            'apiVersion': SYNCSET_API_VERSION,
            'kind': 'SyncSet',
            'metadata': {
                'labels': {
                    'api.openshift.com/id': cluster_id,
                    'api.openshift.com/name': full_cluster_name,
                },
                'name': SYNCSET_NAME,
                'namespace': namespace,
            },
            'spec': {
                'clusterDeploymentRefs': [{
                    'name': trunc_cluster_name,
                }],
                'resourceApplyMode': 'Upsert',
            }
        }

        # do we have a schedule for this cluster?
        if external_id not in cluster_schedules and CATCHALL_CLUSTER_ID not in cluster_schedules:
            logging.warn(
                "Ignoring cluster '{}' as it has no schedule and no default schedule is set.".format(full_cluster_name))
            continue

        schedule_id = external_id if external_id in cluster_schedules else CATCHALL_CLUSTER_ID

        # perform final data sanitation checks
        if not valid_date(cluster_schedules[schedule_id]['upgrade_at']):
            logging.warn('Invalid schedule date for cluster {}, this row will be ignored.'.format(full_cluster_name))
            continue
        if not valid_version(cluster_schedules[schedule_id]['version']):
            logging.warn(
                'Invalid schedule upgrade version for cluster {}, this row will be ignored.'.format(full_cluster_name))
            continue
        if not (cluster_schedules[schedule_id]['channel']).startswith(('stable', 'fast')):
            logging.warn('Invalid channel for cluster {}, this row will be ignored.'.format(full_cluster_name))
            continue

        uc = generate_upgradeconfig(cluster_schedules[schedule_id]['upgrade_at'],
                                    cluster_schedules[schedule_id]['version'],
                                    cluster_schedules[schedule_id]['channel'])
        cluster_syncset['spec']['resources'] = [uc]
        cluster_syncsets.append(cluster_syncset)

    syncset_bundle['items'] = cluster_syncsets

    return syncset_bundle


def output_syncset_bundle(syncsets, file):
    """
    Outputs the supplied syncset bundle dictionary to a JSON-formatted file
    :param syncsets: syncset bundle in dict form
    :param file: file to write to
    """
    with open(file, "w") as syncset_file:
        json.dump(syncsets, syncset_file, indent=4)
    logging.info('Wrote output file: {}'.format(file))


if __name__ == '__main__':
    # program initialization
    init_logging()
    parser = init_argparse()
    args = parser.parse_args()

    # fetch the list of candidate clusters
    cluster_schedules = parse_schedule_file(args.schedule_file)

    # fetch the list of cluster deployments on the cluster
    cluster_deployments = get_all_clusterdeployments()

    # generate the syncset bundle
    syncset_bundle = generate_syncset_bundle(cluster_deployments, cluster_schedules, args.cluster_id)

    # write it out to file
    output_syncset_bundle(syncset_bundle, args.output_file)

