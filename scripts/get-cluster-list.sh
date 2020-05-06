#!/bin/bash

CLUSTER_GROUP=$1

help() {
    echo "$0 {sre,sd,internal,external}"
    exit -1
}

VALID_CLUSTER_GROUP=0

# SREP clusters
LEGALENTITY_IDS_SRE=(1HXb66dsiQCFcwk3tN64c55KORn)

# SD CICD clusters (we do not upgrade these!)
LEGALENTITY_IDS_CICD=(1aV37K1VQv2zSStwSkdwBNOUBGI)

# SD clusters
LEGALENTITY_IDS_SD=(1Lug81OKNgrfq8kMX8C5J2Zzndq 1MK6ieFXd0eu1hERdENAPvpbi7x 1MSRrYaelBWudhmVktupE2t7ABy)

# Internal Customer clusters
LEGALENTITY_IDS_INTERNAL=(1GlYCTDTBmUTij1KYFlUiXFEFQe 1MpZfnmsZeUWjWHg7XRgP15dM9e 1OXqyqko0vmxpV9dmXe9oFypJIw 1PP9KzeLFavv9K3pHGjEgDYfR6V 1Q01Y9f4KNwqGfXJawQU7BQhchI)

# External Customer clusters are anything not in the lists above! ^^

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
    LEGALENTITY_GREP="grep -v -e $(echo ${LEGALENTITY_IDS_SRE[@]} | sed 's/ / -e /g') -e $(echo ${LEGALENTITY_IDS_CICD[@]} | sed 's/ / -e /g') -e $(echo ${LEGALENTITY_IDS_SD[@]} | sed 's/ / -e /g') -e $(echo ${LEGALENTITY_IDS_INTERNAL[@]} | sed 's/ / -e /g')"
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
RAW_DATA=$(oc get clusterdeployment --all-namespaces -o json | jq -rc ".items[] | select(.metadata.namespace | index(\"$(echo $NAMESPACE_LIST | sed 's/ /\",\"/g')\")) | .fqdn = .metadata.name + \".\" + .spec.baseDomain | {shortName: .metadata.name, longName: .metadata.labels[\"api.openshift.com/name\"], namespace: .metadata.namespace, baseDomain: .spec.baseDomain, desiredVersion: .status.clusterVersionStatus.desired.version, fqdn: .fqdn, installed: .spec.installed, deletionTimestamp: .deletionTimestamp}" | xargs | sed 's/{/{"/g' | sed 's/:/":"/g' | sed 's/,/","/g' | sed 's/}/"}/g' | sed 's/ /,/g' | sed 's/"null"/null/g')

echo "{\"items\":[$RAW_DATA]}"
