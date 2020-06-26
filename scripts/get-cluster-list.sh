#!/bin/bash

CLUSTER_GROUP=$1
OPTION=$2

if [ "$OPTION" == "" ];
then
    OPTION="all"
fi

help() {
    echo "$0 {sre,sd,cicd,internal,external,snowflake} {all,nonprod,prod}"
    echo "   first argument is the group of clusters, it is required"
    echo "   second argument is the set subset of clusters, it defaults to 'all'"
    exit -1
}

VALID_CLUSTER_GROUP=0

#####
# How to get organization ID to populate the arrays below:
#       CLUSTER_ID=15uq6splkva07rae2hgih6eph4vs3p8m
#       ocm get $(ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID | jq -r '.subscription.href') | jq -r '.organization_id'
#####

# SREP clusters
LEGALENTITY_IDS_SRE=(1HXb66dsiQCFcwk3tN64c55KORn)

# SD CICD clusters (we do not upgrade these!)
LEGALENTITY_IDS_CICD=(1aV37K1VQv2zSStwSkdwBNOUBGI)

# SD clusters
LEGALENTITY_IDS_SD=(1Lug81OKNgrfq8kMX8C5J2Zzndq 1MK6ieFXd0eu1hERdENAPvpbi7x 1MSRrYaelBWudhmVktupE2t7ABy)

# Internal Customer clusters
LEGALENTITY_IDS_INTERNAL=(1GlYCTDTBmUTij1KYFlUiXFEFQe 1MpZfnmsZeUWjWHg7XRgP15dM9e 1PP9KzeLFavv9K3pHGjEgDYfR6V 1Q01Y9f4KNwqGfXJawQU7BQhchI)

# Grep for first round of external customer clusters, intent to hit non-prod clusters.  This is a GUESS and is OK since we have manual review and have up to now done all clusters at the same time.  This will be replaced w/ customer driven scheduling with the managed-upgrade-operator in the future.
# Do not include 'grep' command, it will be prepended.  This is so we can use -v to exclude from the 'external' target.
GREP_NONPROD='-e dev -e test -e "non[-]prod" -e qa -e "[-]st[-]" -e stage -e staging'

# External Customer clusters are anything not in the lists above with the exception of special scheduling.
# 1OXqyqko0vmxpV9dmXe9oFypJIw is AppSRE, included here to exclude quay clusters
LEGALENTITY_IDS_SNOWFLAKE=(1OXqyqko0vmxpV9dmXe9oFypJIw 1W0oKQFsL4GExEUkSJZ71mTmZEc)

# generated "grep" command to find stuff by legal entity ID
LEGALENTITY_GREP=""

# make sure we have a valid CLUSTER_GROUP and we setup the legal entity grep
case $CLUSTER_GROUP in
"sre")
    VALID_CLUSTER_GROUP=1
    LEGALENTITY_GREP="grep -e $(echo ${LEGALENTITY_IDS_SRE[@]} | sed 's/ / -e /g')"
    ;;
"cicd")
    VALID_CLUSTER_GROUP=1
    LEGALENTITY_GREP="grep -e $(echo ${LEGALENTITY_IDS_CICD[@]} | sed 's/ / -e /g')"
    ;;
"sd")
    VALID_CLUSTER_GROUP=1
    LEGALENTITY_GREP="grep -e $(echo ${LEGALENTITY_IDS_SD[@]} | sed 's/ / -e /g')"
    ;;
"internal")
    VALID_CLUSTER_GROUP=1
    LEGALENTITY_GREP="grep -e $(echo ${LEGALENTITY_IDS_INTERNAL[@]} | sed 's/ / -e /g')"
    ;;
"external")
    VALID_CLUSTER_GROUP=1
    LEGALENTITY_GREP="grep -v -e $(echo ${LEGALENTITY_IDS_SRE[@]} | sed 's/ / -e /g') -e $(echo ${LEGALENTITY_IDS_CICD[@]} | sed 's/ / -e /g') -e $(echo ${LEGALENTITY_IDS_SD[@]} | sed 's/ / -e /g') -e $(echo ${LEGALENTITY_IDS_INTERNAL[@]} | sed 's/ / -e /g') -e $(echo ${LEGALENTITY_IDS_SNOWFLAKE[@]} | sed 's/ / -e /g')"
    ;;
"snowflake")
    VALID_CLUSTER_GROUP=1
    LEGALENTITY_GREP="grep -e $(echo ${LEGALENTITY_IDS_SNOWFLAKE[@]} | sed 's/ / -e /g')"
    ;;
esac

if [ $VALID_CLUSTER_GROUP -ne 1 ];
then
    echo "Invalid argument: $CLUSTER_GROUP"
    help
fi

TEMP_DIR=`mktemp -d`
trap "rm -rf $TEMP_DIR" SIGINT SIGTERM EXIT

# get a list of all namespaces we care about
NAMESPACE_LIST=$((oc get accountclaim --all-namespaces -o json | jq -r '.items[] | .metadata.namespace + " " + .spec.legalEntity.id' && oc get projectclaim --all-namespaces -o json | jq -r '.items[] | .metadata.namespace + " " + .spec.legalEntity.id') | eval $LEGALENTITY_GREP | awk '{print $1}')

# and massage some clusterdeployment output to make it printable and valid json...
# NOTE we assume at least one clusterdeployment exists, else this will hang on the xargs | sed ... stuff
RAW_DATA="{\"items\":[$(oc get clusterdeployment --all-namespaces -o json | jq -rc ".items[] | select(.metadata.namespace | index(\"$(echo $NAMESPACE_LIST | sed 's/ /\",\"/g')\")) | .fqdn = .metadata.name + \".\" + .spec.baseDomain | {id: .metadata.labels[\"api.openshift.com/id\"], externalId: .spec.clusterMetadata.clusterID, shortName: .metadata.name, longName: .metadata.labels[\"api.openshift.com/name\"], namespace: .metadata.namespace, baseDomain: .spec.baseDomain, desiredVersion: .status.clusterVersionStatus.desired.version, fqdn: .fqdn, installed: .spec.installed, deletionTimestamp: .deletionTimestamp}" | xargs | sed 's/{/{"/g' | sed 's/:/":"/g' | sed 's/,/","/g' | sed 's/}/"}/g' | sed 's/ /,/g' | sed 's/"null"/null/g')]}"


# NOTE for "nonprod" and "prod" use the cluster IDs else the jq select | index will match clusters in both nonprod and prod in some cases

case $OPTION in
"nonprod")
    CLUSTER_IDS=$(echo $RAW_DATA | jq -r '.items[] | .longName + "," + .id' | eval grep $GREP_NONPROD | sed 's/.*,\(.*\)/\1/g')
    if [ "$CLUSTER_IDS" == "" ];
    then
        RAW_DATA="{\"items\":[]}"
    else
        RAW_DATA="{\"items\":[$(echo $RAW_DATA | jq -rc ".items[] | select(.id | index(\"$(echo $CLUSTER_IDS | sed 's/ /\",\"/g')\"))" | xargs | sed 's/{/{"/g' | sed 's/:/":"/g' | sed 's/,/","/g' | sed 's/}/"}/g' | sed 's/ /,/g' | sed 's/"null"/null/g')]}"
    fi
    ;;
"prod")
    # only difference from 'nonprod' is -v for $GREP_NONPROD
    CLUSTER_IDS=$(echo $RAW_DATA | jq -r '.items[] | .longName + "," + .id' | eval grep -v $GREP_NONPROD | sed 's/.*,\(.*\)/\1/g')
    if [ "$CLUSTER_IDS" == "" ];
    then
        RAW_DATA="{\"items\":[]}"
    else
        RAW_DATA="{\"items\":[$(echo $RAW_DATA | jq -rc ".items[] | select(.id | index(\"$(echo $CLUSTER_IDS | sed 's/ /\",\"/g')\"))" | xargs | sed 's/{/{"/g' | sed 's/:/":"/g' | sed 's/,/","/g' | sed 's/}/"}/g' | sed 's/ /,/g' | sed 's/"null"/null/g')]}"
    fi
    ;;
"all")
    # nothing to do, return everything
    ;;
esac

echo $RAW_DATA
