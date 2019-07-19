#!/bin/bash

OCP_VERSION_FROM=$1
OCP_VERSION_TO=$2

if [ -z $OCP_VERSION_FROM ];
then
    echo "This script can be used to get the status of all managed clusters or to upgrade clusters."
    echo "usage: $0 status"
    echo "usage: $0 <from> <to>"
    echo "  example: $0 4.1.0 4.1.2"
    exit 1
fi

if [ "$OCP_VERSION_FROM" == "status" ];
then
    # absense of versions implies status check
    unset OCP_VERSION_FROM
    unset OCP_VERSION_TO
fi

UPGRADE_STARTED=""
UPGRADE_PROGRESSING=""
UPGRADE_NOT_POSSIBLE=""
UPGRADE_DONE=""

NOW_EPOCH=$(date +"%s")

if [ -n $OCP_VERSION_FROM ];
then
    # Verify we can actually upgrade (is this in the graph)
    CHANNEL_NAME=$(echo "${OCP_VERSION_TO}" | sed 's/\([^.]*\.[^.]*\)\..*/stable-\1/g')
    GRAPH=$(curl -s -H "Accept: application/json" https://api.openshift.com/api/upgrades_info/v1/graph?channel="${CHANNEL_NAME}")
    GRAPH_INDEX_FROM=$(echo "${GRAPH}" | jq -r "[ .nodes[] | .version == \"$OCP_VERSION_FROM\" ] | index(true)")
    GRAPH_INDEX_TO=$(echo "${GRAPH}" | jq -r "[ .nodes[] | .version == \"$OCP_VERSION_TO\" ] | index(true)")

    GRAPH_EDGE=$(echo "${GRAPH}" | jq -r ".edges[] | select(.[0] == $GRAPH_INDEX_FROM) | .[1] == $GRAPH_INDEX_TO" | grep true)

    if [ -z $GRAPH_INDEX_FROM ];
    then
        echo "Cannot upgrade from $OCP_VERSION_FROM, it is not available in upgrade graph."
        exit 2
    fi
    if [ -z $GRAPH_INDEX_TO ];
    then
        echo "Cannot upgrade to $OCP_VERSION_TO, it is not available in upgrade graph."
        exit 2
    fi
    if [ "$GRAPH_EDGE" != "true" ];
    then
        echo "Cannot upgrade from $OCP_VERSION_FROM to $OCP_VERSION_TO, no path exists in upgrade graph."
        exit 2
    fi

    # Verify the target version exists as a ClusterImageSet (CIS) on the cluster
    # (if not, the customer could never install to that target version)
    CIS_VERSION=$(oc get clusterimageset --all-namespaces -o json | jq -r ".items[].spec.releaseImage | split(\":\")[1] | select(. == \"$OCP_VERSION_TO\")")
    if [ "$OCP_VERSION_TO" != "$CIS_VERSION" ];
    then
        echo "Cannot upgrade to $OCP_VERSION_TO, it is not available as a ClusterImageSet in the cluster."
        exit 3
    fi

    # Verify we have ClusterDeployment CRs to work with
    if [ `oc get crd clusterdeployments.hive.openshift.io --no-headers 2>/dev/null | wc -l` == "0" ];
    then
        echo "ERROR: Current cluster does not have Hive installed.  Verify where you are logged in."
        exit 1
    fi
fi

TMP_DIR=`mktemp -d`
OCP_PATCH="{\"spec\":{\"desiredUpdate\": {\"force\": false, \"image\": \"\", \"version\": \"$OCP_VERSION_TO\"}}}"
if [[ $? -ne 0 ]];
then
    echo "ERROR: Couldn't create a temporary directory. Aborting.
    exit 1
fi
# kick off the upgrades (or status check)
for CD_NAMESPACE in `oc get clusterdeployment --all-namespaces | awk '{print $1}' | sort | uniq`;
do  
    for CD_NAME in `oc -n $CD_NAMESPACE get clusterdeployment -o json | jq -r '.items[] | select(.metadata.labels["api.openshift.com/managed"] == "true") | select(.status.installed == true) | select(.status.clusterVersionStatus.history[0].state == "Completed") | .metadata.name'`;
    do  
        echo -n "Checking $CD_NAME..."
        # TODO figure out how to get the latest version, for now just getting the first one (ordered descending)
        OCP_CURRENT_VERSION=`oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.status.clusterVersionStatus.history[] | select(.state == "Completed") | .version' | head -n1`

        SS_NAME=$CD_NAME-upgrade
        SS_VERSION_FROM=`oc -n $CD_NAMESPACE get syncset $SS_NAME --show-labels --no-headers 2> /dev/null | sed 's|.*managed.openshift.io/from=\([^,]*\).*|\1|g'`
        SS_VERSION_TO=`oc -n $CD_NAMESPACE get syncset $SS_NAME --show-labels --no-headers 2> /dev/null | sed 's|.*managed.openshift.io/to=\([^,]*\).*|\1|g'`
        SS_CREATED_ON=$(date --date="$(oc -n $CD_NAMESPACE get syncset $SS_NAME --template '{{ .metadata.creationTimestamp }}' 2>/dev/null)" +"%s" 2>/dev/null)
        SS_AGE_MIN=$(($(($NOW_EPOCH-$SS_CREATED_ON))/60))

        # always report status
        echo "done ($OCP_CURRENT_VERSION)"

        if [ -n $OCP_VERSION_FROM ];
        then
            # upgrade

            # do nothing if the current version in SS is what we got out of CD
            if [ "$OCP_CURRENT_VERSION" == "$SS_VERSION_FROM" ];
            then
                UPGRADE_PROGRESSING="${UPGRADE_PROGRESSING}  $CD_NAME ($SS_VERSION_FROM->$SS_VERSION_TO) [age=$SS_AGE_MIN(min)]\n"
                continue
            fi

            if [ "$OCP_CURRENT_VERSION" == "$OCP_VERSION_FROM" ];
            then
                SS_FILENAME=$TMP_DIR/$SS_NAME.syncset.yaml
                cat << EOF > $SS_FILENAME
apiVersion: hive.openshift.io/v1alpha1
kind: SyncSet
metadata:
  name: $SS_NAME
  namespace: $CD_NAMESPACE
  labels:
    managed.openshift.io/from: "$OCP_CURRENT_VERSION"
    managed.openshift.io/to: "$OCP_VERSION_TO"
spec:
  clusterDeploymentRefs:
  - name: $CD_NAME
  resourceApplyMode: Sync
  patches:
  - apiVersion: config.openshift.io/v1
    applyMode: ApplyOnce
    kind: ClusterVersion
    name: version
    patch: '$OCP_PATCH'
    patchType: merge
EOF

                oc -n $CD_NAMESPACE create -f $SS_FILENAME || oc -n $CD_NAMESPACE replace -f $SS_FILENAME
                UPGRADE_STARTED="${UPGRADE_STARTED}  $CD_NAME ($OCP_VERSION_FROM->$OCP_VERSION_TO)\n"
            elif [ -z $SS_VERSION_FROM ] && [ "$OCP_CURRENT_VERSION" != "$OCP_VERSION_TO" ];
            then
                # report can't upgrade if version is not upgradable and upgrade is not in progress
                UPGRADE_NOT_POSSIBLE="${UPGRADE_NOT_POSSIBLE}  $CD_NAME ($OCP_CURRENT_VERSION)\n"
            else
                # cluster is already upgraded?
                if [ -z $SS_VERSION_FROM ];
                then
                    # delete the syncset, it's not needed anymore
                    oc -n $CD_NAMESPACE delete SyncSet $SS_NAME
                    UPGRADE_DONE="${UPGRADE_DONE}  $CD_NAME ($OCP_CURRENT_VERSION)\n"
                fi
            fi
        fi
    done
done

rm -rf $TMP_DIR

if [ -n $OCP_VERSION_FROM ];
then
    echo -e "\nUpgrades started:\n$UPGRADE_STARTED"
    echo -e "Upgrades in progress:\n$UPGRADE_PROGRESSING"
    echo -e "Upgrades completed:\n$UPGRADE_DONE"
    echo -e "Upgrades not possible:\n$UPGRADE_NOT_POSSIBLE"
fi

