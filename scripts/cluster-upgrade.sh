#!/bin/bash
# This script contains non-portable components and is intended to run on a Hive cluster.

# make sure if the script is killed all child processes are killed:
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

OCP_VERSION_FROM=$1
OCP_VERSION_TO=$2
CLUSTER_NAMES=${@:3}

TMP_DIR=$(mktemp -d)
if [[ $? -ne 0 ]];
then
    echo "ERROR: Couldn't create a temporary directory. Aborting."
    exit 1
fi

if [ -z "$CLUSTER_NAMES" ];
then
    echo "This script is used to upgrade clusters from a version to another."
    echo "Optionally can target a subset of clusters by name."
    echo "When upgrading all, must specify 'all' for cluster name."
    echo ""
    echo "usage: $0 <from> <to> [cluster name1] .. [cluster nameN]"
    echo "  example: $0 4.1.0 4.1.2 all"
    echo "  example: $0 4.1.0 4.1.2 nmalik1 nmalik2"
    exit 1
fi

if [ "$OCP_VERSION_FROM" == "status" ];
then
    # absense of versions implies status check
    unset OCP_VERSION_FROM
    unset OCP_VERSION_TO
fi

log() {
    NAME=$1
    STAGE=$2
    MESSAGE=$3

    MESSAGE=$(echo $MESSAGE | sed 's/\(.*\),$/\1/g')
    
    echo "$(date "+%Y-%m-%d_%H.%M.%S") - $NAME - $STAGE - $MESSAGE"
}

# Compares two version strings together to determine which is more recent.
# First parameter is the requested version
# Second parameter is the max allowed version.
# If the candidate > check, or either version are omitted, return 1. Otherwise return 0
# Functionally this is used to determine if the requested (candidate) version exceeds the maximum allowed version (check).
# This relies on Bash (due to input redirection), and sort to do the comparing
vercomp() {
    local requested_version=$1 max_allowed_version=$2 sort_result=
    sort_result=$(sort --version-sort <(echo $requested_version) <(echo $max_allowed_version) | tail -n1)
    if [[ $requested_version == $sort_result && $requested_version != $max_allowed_version ]]; then
        return 1
    else
        return 0
    fi
}

setup() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3

    # get kubeconfig so we can check status of cluster's nodes (extra capacity)
    oc -n $CD_NAMESPACE extract "$(oc -n $CD_NAMESPACE get secrets -o name | grep $CD_NAME | grep kubeconfig)" --keys=kubeconfig --to=- > ${TMP_DIR}/kubeconfig-${CD_NAMESPACE}

    ORIGINAL_REPLICAS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.metadata.labels["managed.openshift.io/original-worker-replicas"] | select(. != null)')
    DESIRED_REPLICAS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.spec.compute[] | select(.name | startswith("worker")) | .replicas')
    ZONE_COUNT=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.spec.compute[] | select(.name | startswith("worker")) | .platform.aws.zones[]' | wc -l)

    if [ "$ORIGINAL_REPLICAS" == "" ];
    then
        # nope, need to bump replicas!
        ORIGINAL_REPLICAS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.spec.compute[0].replicas')
        DESIRED_REPLICAS=$(($ORIGINAL_REPLICAS+$ZONE_COUNT))

        # update replicas
        oc -n $CD_NAMESPACE label clusterdeployment $CD_NAME managed.openshift.io/original-worker-replicas=$ORIGINAL_REPLICAS
        oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r ".spec.compute[0].replicas=$DESIRED_REPLICAS" | oc replace -f -

        log $OCM_NAME "setup" "bumping replicas from $ORIGINAL_REPLICAS to $DESIRED_REPLICAS"
    fi

    # make sure we are at capacity in cluster
    MS_REPLICAS=$(($DESIRED_REPLICAS/$ZONE_COUNT))
    for MS_NAME in $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-machine-api get machineset --no-headers | grep worker | awk '{print $1}');
    do
        log $OCM_NAME "setup" "waiting for replicas, machineset=$MS_NAME"
        AVAILABLE_REPLICAS=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-machine-api get machineset $MS_NAME -o jsonpath='{.status.availableReplicas}')

        while [ "$AVAILABLE_REPLICAS" != "$MS_REPLICAS" ];
        do
            sleep 15

            AVAILABLE_REPLICAS=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-machine-api get machineset $MS_NAME -o jsonpath='{.status.availableReplicas}')
        done

        log $OCM_NAME "setup" "replicas are ready for upgrade, machineset=$MS_NAME"
    done
}

upgrade() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3
    FROM=$4
    TO=$5
    
    log $OCM_NAME "upgrade" "Checking $OCM_NAME..."

    # - do we need to upgrade?
    OCP_CURRENT_VERSION=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.status.clusterVersionStatus.history[] | select(.state == "Completed") | .version' | head -n1)

    if [ "$OCP_CURRENT_VERSION" == "$TO" ];
    then
        log $OCM_NAME "upgrade" "skipping, already on version $TO"
        teardown $OCM_NAME $CD_NAMESPACE $CD_NAME
        return
    fi

    if [ "$OCP_CURRENT_VERSION" != "$FROM" ];
    then
        log $OCM_NAME "upgrade" "skipping, expect version $FROM, found version $OCP_CURRENT_VERSION"
        return
    fi

    setup $OCM_NAME $CD_NAMESPACE $CD_NAME

    # is upgrade already progressing?
    IN_PROGRESS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r ".status.clusterVersionStatus.history[] | select(.version == \"$TO\") | .version" | grep -v null)

    if [ "$IN_PROGRESS" == "" ];
    then
        # hive doesn't know about this version.. try to start the upgrade
        log $OCM_NAME "upgrade" "upgrading from $FROM to $TO"

        oc -n $CD_NAMESPACE extract "$(oc -n $CD_NAMESPACE get secrets -o name | grep $CD_NAME | grep kubeconfig)" --keys=kubeconfig --to=- > ${TMP_DIR}/kubeconfig-${CD_NAMESPACE}
        CHANNEL_NAME=$(get_channel $TO)

        KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc patch clusterversion version --type merge -p "{\"spec\":{\"channel\": \"$CHANNEL_NAME\"}}"
        sleep 15
        KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc patch clusterversion version --type merge -p "{\"spec\":{\"desiredUpdate\": {\"version\": \"$TO\"}}}"
    fi

    # 3. wait for upgrade to complete
    log $OCM_NAME "upgrade" "waiting for cluster version"
    OCP_CURRENT_VERSION=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.status.clusterVersionStatus.history[] | select(.state == "Completed") | .version' | head -n1)
    
    while [ "$OCP_CURRENT_VERSION" != "$TO" ];
    do
        sleep 15
        OCP_CURRENT_VERSION=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.status.clusterVersionStatus.history[] | select(.state == "Completed") | .version' | head -n1)

        # check several things about the cluster and report problems
        # * api availability
        # * degraded operators
        # * critical alerts
        # * count of pods in state not "Running" or "Completed"

        API_RESPONSE=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get --raw /api 2>&1)
        API_VERSION=$(echo $API_RESPONSE | jq -r '.versions[]' || echo "FAIL")

        if [ "$API_VERSION" == "v1" ];
        then
            OUTPUT="$OUTPUT,\"API=OK\""
        else
            log $OCM_NAME "upgrade" "INFO: API requests are failing, msg = $API_RESPONSE"
            # don't bother with other checks, there is a good chance they won't work
            continue
        fi

        DCO=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusteroperator --no-headers | awk '{print $1 "," $5}' | grep -v ",False" | awk -F, '{print $1 ","}' | xargs)
        
        if [ "$DCO" != "" ];
        then
            log $OCM_NAME "upgrade" "INFO: Degraded Operators = $DCO"
        fi

        CA=$(curl -G -s -k -H "Authorization: Bearer $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-monitoring sa get-token prometheus-k8s)" --data-urlencode "query=ALERTS{alertstate!=\"pending\",severity=\"critical\"}" "https://$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-monitoring get routes prometheus-k8s -o json | jq -r .spec.host)/api/v1/query" | jq -r '.data.result[].metric.alertname' | tr '\n' ',' )

        if [ "$CA" != "" ];
        then
            log $OCM_NAME "upgrade" "WARNING: Critical Alerts = $CA"
        fi

        POD_ISSUES=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get pods --all-namespaces --no-headers | grep -v -e Running -e Completed -e Terminating -e ContainerCreating -e Init -e Pending | grep -e ^default -e ^kube -e ^openshift)
        PPC=$(echo "$POD_ISSUES" | grep -v "^$" | wc -l)
        
        if [ "$PPC" != "0" ];
        then
            log $OCM_NAME "upgrade" "INFO: Problem Pod Count = $PPC
$POD_ISSUES"
        fi
    done

    log $OCM_NAME "upgrade" "ClusterVersion on $TO"
    log $OCM_NAME "upgrade" "checking kubelet versions"

    # fun fact!  after clusterversion says it is done, individual nodes could still be updated.
    # make sure all nodes run same kubelet version
    KUBELET_VERSION_COUNT=0
    while [ "$KUBELET_VERSION_COUNT" != "1" ];
    do
        KUBELET_VERSION_COUNT=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get nodes --no-headers -o custom-columns=VERSION:.status.nodeInfo.kubeletVersion | sort | uniq | wc -l)

        sleep 15
    done

    log $OCM_NAME "upgrade" "all kubelets on same version"
    log $OCM_NAME "upgrade" "upgrade is complete"

    teardown $OCM_NAME $CD_NAMESPACE $CD_NAME
}

teardown() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3

    ORIGINAL_REPLICAS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.metadata.labels["managed.openshift.io/original-worker-replicas"] | select(. != null)' 2>/dev/null)
    DESIRED_REPLICAS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.spec.compute[] | select(.name | startswith("worker")) | .replicas')

    if [ "$ORIGINAL_REPLICAS" != "" ] && [ "$ORIGINAL_REPLICAS" != "$DESIRED_REPLICAS" ];
    then
        # need to set replicas back to the original and clear the label
        oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r ".spec.compute[0].replicas=$ORIGINAL_REPLICAS" | oc replace -f -
        oc -n $CD_NAMESPACE label clusterdeployment $CD_NAME managed.openshift.io/original-worker-replicas-

        log $OCM_NAME "teardown" "dropping replicas back from $DESIRED_REPLICAS to $ORIGINAL_REPLICAS"
    fi
}

get_channel() {
    VERSION=$1

    VERSION_MINOR=$(echo "${VERSION}" | sed 's/\([^.]*\.[^.]*\)\..*/\1/g')
    
    if [ "$VERSION_MINOR" == "4.1" ];
    then
        CHANNEL_NAME="stable-$VERSION_MINOR"
    else
        CHANNEL_NAME="fast-$VERSION_MINOR"
    fi

    echo $CHANNEL_NAME
}

if [[ -n $OCP_VERSION_FROM ]];
then
    # Verify we can actually upgrade (is this in the graph)
    CHANNEL_NAME=$(get_channel $OCP_VERSION_TO)
    GRAPH=$(curl -s -H "Accept: application/json" https://api.openshift.com/api/upgrades_info/v1/graph?channel="${CHANNEL_NAME}&arch=amd64&version=$OCP_VERSION_TO")
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
fi

# Verify we have ClusterDeployment CRs to work with
if [ `oc get crd clusterdeployments.hive.openshift.io --no-headers 2>/dev/null | wc -l` == "0" ];
then
    echo "ERROR: Current cluster does not have Hive installed.  Verify where you are logged in."
    exit 1
fi

if [[ -n $OCP_VERSION_TO ]];
then
    # Verify the target version exists as a ClusterImageSet (CIS) on the cluster
    # (if not, the customer could never install to that target version)
    CIS_VERSION=$(oc get clusterimageset --all-namespaces -o json | jq -r ".items[].spec.releaseImage | split(\":\")[1] | select(. == \"$OCP_VERSION_TO\")")
    if [ "$OCP_VERSION_TO" != "$CIS_VERSION" ];
    then
        echo "Cannot upgrade to $OCP_VERSION_TO, it is not available as a ClusterImageSet in the cluster."
        exit 3
    fi

    # Get the default install ClusterImageSet (CIS)
    # Gets first item, but there should only be 1
    CIS_VERSION_DEFAULT=$(oc get clusterimageset --all-namespaces -l api.openshift.com/default=true -o json | jq -r ".items[0].spec.releaseImage | split(\":\")[1]")
    # Verify the target version is <= default CIS version
    if ! vercomp "${OCP_VERSION_TO}" "${CIS_VERSION_DEFAULT}";
    then
        echo "Cannot upgrade past Default ClusterImageSet ${CIS_VERSION_DEFAULT}"
        exit 4
    fi
fi

for CD_NAMESPACE in `oc get clusterdeployment --all-namespaces | awk '{print $1}' | sort | uniq`;
do  
    for CD_NAME in `oc -n $CD_NAMESPACE get clusterdeployment -o json | jq -r '.items[] | select(.metadata.labels["api.openshift.com/managed"] == "true") | select(.status.installed == true) | select(.status.clusterVersionStatus.history[0].state == "Completed") | .metadata.name'`;
    do  
        if [ "$CLUSTER_NAMES" != "all" ];
        then
            PROCESS=0
            OCM_NAME=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.metadata.labels["api.openshift.com/name"]')
            for CLUSTER_NAME in $CLUSTER_NAMES
            do
                if [ "$OCM_NAME" == "$CLUSTER_NAME" ];
                then
                    # a match, process it
                    PROCESS=1
                    break
                fi
            done

            if [ "$PROCESS" == "0" ];
            then
                # not one to process, skip it
                continue
            fi
        fi
        upgrade $OCM_NAME $CD_NAMESPACE $CD_NAME $OCP_VERSION_FROM $OCP_VERSION_TO &
    done
done

wait

rm -rf $TMP_DIR

