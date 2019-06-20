 #!/bin/bash

OCP_VERSION_FROM=$1
OCP_VERSION_TO=$2

if [ "$OCP_VERSION_TO" == "" ];
then
    echo "usage: $0 <from> <to>"
    echo "example: $0 4.1.0 4.1.2"
    exit 1
fi

UPGRADE_NOT_POSSIBLE=""
UPGRADE_PROGRESSING=""
UPGRADE_DONE=""

NOW_EPOCH=$(date +"%s")

# Verify we can actually upgrade (is this in the graph)
CHANNEL_NAME=$(echo $OCP_VERSION_TO | sed 's/\([^.]*\.[^.]*\)\..*/stable-\1/g')
GRAPH_VERSION=$(curl -s -H "Accept: application/json" https://api.openshift.com/api/upgrades_info/v1/graph?channel=$CHANNEL_NAME | jq -r ".nodes[] | select(.version == \"$OCP_VERSION_TO\") | .version")

if [ "$OCP_VERSION_TO" != "$GRAPH_VERSION" ];
then
    echo "Cannot upgrade to $OCP_VERSION_TO, it is available in upgrade graph."
    exit 2
fi


# Verify we have ClusterDeployment CRs to work with
if [ `oc get crd clusterdeployments.hive.openshift.io --no-headers 2>/dev/null | wc -l` == "0" ];
then
    echo "ERROR: Current cluster does not have Hive installed.  Verify where you are logged in."
    exit 1
fi

# kick off the upgrades
for CD_NAMESPACE in `oc get clusterdeployment --all-namespaces | awk '{print $1}' | sort | uniq`;
do
    for CD_NAME in `oc -n $CD_NAMESPACE get clusterdeployment -o json | jq -r '.items[] | select(.metadata.labels["api.openshift.com/managed"] == "true") | select(.status.installed == true) | select(.status.clusterVersionStatus.history[0].state == "Completed") | .metadata.name'`;
    do
        echo -n "Checking $CD_NAME..."
        # TODO figure out how to get the latest version, for now just getting the first one (ordered descending)
        OCP_CURRENT_VERSION=`oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.status.clusterVersionStatus.history[] | select(.state == "Completed") | .version' | head -n1`

        SS_NAME=$CD_NAME-upgrade
        SS_CURRENT_VERSION=`oc -n $CD_NAMESPACE get syncset $SS_NAME --show-labels --no-headers 2> /dev/null | sed 's|.*managed.openshift.io/from=\([^,]*\).*|\1|g'`
        SS_CREATED_ON=$(date --date="$(oc -n $CD_NAMESPACE get syncset $SS_NAME --template '{{ .metadata.creationTimestamp }}' 2>/dev/null)" +"%s" 2>/dev/null)
        
        SS_AGE_MIN=$(($(($NOW_EPOCH-$SS_CREATED_ON))/60))

        # do nothing if the current version in SS is what we got out of CD
        if [ "$OCP_CURRENT_VERSION" == "$SS_CURRENT_VERSION" ];
        then
            echo "done ($OCP_CURRENT_VERSION)"
            UPGRADE_PROGRESSING="${UPGRADE_PROGRESSING}$CD_NAME ($OCP_CURRENT_VERSION) [age=$SS_AGE_MIN(min)]\n"
            continue
        fi

        if [ "$OCP_CURRENT_VERSION" == "$OCP_VERSION_FROM" ];
        then
            OCP_PATCH="{\"spec\":{\"desiredUpdate\": {\"force\": false, \"image\": \"\", \"version\": \"$OCP_VERSION_TO\"}}}"
        elif [ "$SS_CURRENT_VERSION" == "" ] && [ "$OCP_CURRENT_VERSION" != "$OCP_VERSION_TO" ];
        then
            # report can't upgrade if version is not upgradable and upgrade is not in progress
            echo "done ($OCP_CURRENT_VERSION)"
            UPGRADE_NOT_POSSIBLE="${UPGRADE_NOT_POSSIBLE}$CD_NAME ($OCP_CURRENT_VERSION)\n"
            continue
        else
            # cluster is already upgraded?
            echo "done ($OCP_CURRENT_VERSION)"
            if [ "$SS_CURRENT_VERSION" != "" ];
            then
                # delete the syncset, it's not needed anymore
                oc -n $CD_NAMESPACE delete SyncSet $SS_NAME                
                UPGRADE_DONE="${UPGRADE_DONE}$CD_NAME ($OCP_CURRENT_VERSION)\n"
            fi
            continue
        fi

        SS_FILENAME=$SS_NAME.syncset.yaml
        rm -f $SS_FILENAME
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

    oc $CD_NAMESPACE create -f $SS_FILENAME || oc $CD_NAMESPACE replace -f $SS_FILENAME
    rm -f $SS_FILENAME
    echo "Created SyncSet for '$CD_NAME' upgrade: $OCP_CURRENT_VERSION -> $OCP_VERSION_TO"
    done
done

echo -e "\nUpgrades in progress for:\n$UPGRADE_PROGRESSING"
echo -e "Upgrades not possible for:\n$UPGRADE_NOT_POSSIBLE"
echo -e "Upgrades that have completed:\n$UPGRADE_DONE"

