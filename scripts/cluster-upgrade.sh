#!/bin/bash
# This script contains non-portable components and is intended to run on a Hive cluster.

# make sure if the script is killed all child processes are killed:
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

PD_MAINT_DESCRIPTION_BASE="OSD v4 Cluster Upgrade Control Plane"
PD_MAINT_DESCRIPTION_WORKERS="OSD v4 Cluster Upgrade Nodes"

# base single-az cluster takes about this long to upgrade
PD_MAINT_BASE_MIN=90

# base cluster, single-az, is 4 workers + 1 worker for extra capacity on upgrade
PD_MAINT_BASE_NODE_COUNT=5
PD_MAINT_BASE_INFRA_COUNT=3

# additional time to upgrade per node beyond the base count
PD_MAINT_ADDITIONAL_NODE_MIN=8

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

    prepare_kubeconfig $OCM_NAME $CD_NAMESPACE $CD_NAME

    # do initial check of state only if not already upgrading
    DESIRED_VERSION=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusterversion version -o json | jq -r '.spec.desiredUpdate.version')

    if [ "$DESIRED_VERSION" != "$TO" ];
    then
        # start with it "bad" to force a check, which will continue until it's good
        CLUSTER_STATUS=0

        while [ "$CLUSTER_STATUS" != "1" ];
        do
            check_cluster_status $OCM_NAME $CD_NAMESPACE $CD_NAME "setup"
            if [ "$CLUSTER_STATUS" == "0" ];
            then
                log $OCM_NAME "setup" "ERROR: cluster state needs fixed, see prior logs (UPGRADE BLOCKED)"
                sleep 15
            fi
        done
    fi

    ORIGINAL_REPLICAS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.metadata.labels["managed.openshift.io/original-worker-replicas"] | select(. != null)')
    DESIRED_REPLICAS=$(oc -n $CD_NAMESPACE get machinepool "$CD_NAME-worker" -o json | jq -r '.spec.replicas')
    ZONE_COUNT=$(oc -n $CD_NAMESPACE get machinepool "$CD_NAME-worker" -o json | jq -r '.spec.platform.aws.zones[]' | wc -l)

    if [ "$ORIGINAL_REPLICAS" == "" ];
    then
        # nope, need to bump replicas!
        ORIGINAL_REPLICAS=$(oc -n $CD_NAMESPACE get machinepool "$CD_NAME-worker" -o json | jq -r '.spec.replicas')
        DESIRED_REPLICAS=$(($ORIGINAL_REPLICAS+$ZONE_COUNT))

        # update replicas
        oc -n $CD_NAMESPACE label clusterdeployment $CD_NAME managed.openshift.io/original-worker-replicas=$ORIGINAL_REPLICAS
        oc -n $CD_NAMESPACE get machinepool "$CD_NAME-worker" -o json | jq -r ".spec.replicas=$DESIRED_REPLICAS" | oc replace -f -

        log $OCM_NAME "setup" "bumping replicas from $ORIGINAL_REPLICAS to $DESIRED_REPLICAS"
    fi

    # make sure we are at capacity in cluster
    MS_REPLICAS=$(($DESIRED_REPLICAS/$ZONE_COUNT))
    for MS_NAME in $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-machine-api get machineset --no-headers | grep worker | awk '{print $1}');
    do
        AVAILABLE_REPLICAS=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-machine-api get machineset $MS_NAME -o jsonpath='{.status.availableReplicas}')

        while [ "$AVAILABLE_REPLICAS" != "$MS_REPLICAS" ];
        do
            log $OCM_NAME "setup" "waiting for replicas, machineset=$MS_NAME"

            # sign CSRs, sometimes new node provisioning is stuck because of this
            # https://github.com/openshift/ops-sop/blob/master/v4/alerts/NoNodeObjectForMachineCriticalSRE.md
            for CSR in $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get csr --no-headers 2>/dev/null | grep Pending | awk '{print $1}');
            do
                KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc adm certificate approve $CSR
            done

            sleep 30

            AVAILABLE_REPLICAS=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-machine-api get machineset $MS_NAME -o jsonpath='{.status.availableReplicas}')
        done

        log $OCM_NAME "setup" "replicas are ready for upgrade, machineset=$MS_NAME"
    done

    # Set the initial maintenance window to the base so control plane issues will page earlier for very large clusters.
    setup_maintenance_window $OCM_NAME $CD_NAMESPACE $CD_NAME $PD_MAINT_BASE_MIN "$PD_MAINT_DESCRIPTION_BASE"
}

setup_maintenance_window() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3
    MAINT_WINDOW_MIN=$4
    MAINT_DESC=$5

    # start maintenance in PagerDuty (if not already in mainteance)
    PD_API_KEY=$(oc -n pagerduty-operator get secrets pagerduty-api-key -o json | jq -r '.data.PAGERDUTY_API_KEY' | base64 --decode)

    CD_DOMAIN=$(oc get clusterdeployment -n $CD_NAMESPACE $CD_NAME -o json | jq -r ".spec.baseDomain")

    # search PD with cluster FQDN (could be full serivce name, but that might change)
    CLUSTER_FQDN="$CD_NAME.$CD_DOMAIN"

    PD_SERVICE_ID=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/services?time_zone=UTC&sort_by=name&query=$CLUSTER_FQDN" | jq -r '.services[0].id')

    # sanity check the service ID is for the cluster
    PD_OK=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/services/$PD_SERVICE_ID" | grep $CD_NAME | wc -l)

    # if we didn't get the specific service we expect, skip mainteance
    # if we got null the service doesn't exist
    # if we got "" there is a configuration issue (nothing we can do)

    if [ $PD_OK > 0 ] && [ "$PD_SERVICE_ID" != "null" ] && [ "$PD_SERVICE_ID" != "" ];
    then
        # search for existing maintenance ID
        # IMPORTANT: description must match, else we might remove maintenance put in place for other reasons.
        PD_MAINT_ID=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/maintenance_windows?service_ids%5B%5D=$PD_SERVICE_ID&query=$(echo $MAINT_DESC | tr ' ' '+')&filter=open" | jq -r 'select(.maintenance_windows != null) | .maintenance_windows[0].id')

        # if we got null maintenance doesn't exist
        # if we got "" there is a configuration issue (nothing we can do)

        if [ "$PD_MAINT_ID" == "null" ];
        then
            # create a maintenance for this cluster
         
            # TODO use a real value.. this would break if nmalik leaves SRE!
            PD_USER_EMAIL=nmalik@redhat.com

            DATE_FROM=$(date +"%Y-%m-%dT%H:%M:%S%:z")
            DATE_TO=$(date -d "now + $MAINT_WINDOW_MIN minutes" +"%Y-%m-%dT%H:%M:%S%:z")

            curl --max-time 10 -s -X POST -H 'Accept: application/vnd.pagerduty+json;version=2' -H 'Content-Type: application/json' -H "Authorization: Token token=$PD_API_KEY" -H "From: $PD_USER_EMAIL" -d "{
                \"maintenance_window\": {
                    \"type\": \"maintenance_window\",
                    \"start_time\": \"$DATE_FROM\",
                    \"end_time\": \"$DATE_TO\",
                    \"description\": \"$MAINT_DESC\",
                    \"services\": [
                        {
                            \"id\": \"$PD_SERVICE_ID\",
                            \"type\": \"service_reference\"
                        }
                    ]
                }
            }" 'https://api.pagerduty.com/maintenance_windows' > /dev/null

            PD_MAINT_ID=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/maintenance_windows?service_ids%5B%5D=$PD_SERVICE_ID&query=$(echo $MAINT_DESC | tr ' ' '+')&filter=open" | jq -r 'select(.maintenance_windows != null) | .maintenance_windows[0].id')

            if [ "$PD_MAINT_ID" != "null" ] && [ "$PD_MAINT_ID" != "" ];
            then
                log $OCM_NAME "setup" "INFO: maintenance created for $MAINT_WINDOW_MIN minutes = '$MAINT_DESC'"
            else
                log $OCM_NAME "setup" "WARNING: maintenance failed to create = '$MAINT_DESC' for $MAINT_WINDOW_MIN minutes"
            fi
        else
            log $OCM_NAME "setup" "INFO: mainteance already created, skipping = '$MAINT_DESC'"
        fi
    else
        log $OCM_NAME "setup" "WARNING: maintenance failed to create, no service exists"
    fi

    unset PD_API_KEY
}

upgrade() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3
    FROM=$4
    TO=$5

    prepare_kubeconfig $OCM_NAME $CD_NAMESPACE $CD_NAME
    
    log $OCM_NAME "upgrade" "Checking $OCM_NAME..."

    # do we need to upgrade?
    OCP_CURRENT_VERSION=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusterversion version -o json | jq -r '.status.history[] | select(.state == "Completed") | .version' | grep $FROM)
    KUBELET_VERSION_COUNT=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get nodes --no-headers -o custom-columns=VERSION:.status.nodeInfo.kubeletVersion | sort -u | wc -l)

    if [ "$OCP_CURRENT_VERSION" == "$TO" ] && [ "$KUBELET_VERSION_COUNT" == "1" ];
    then
        log $OCM_NAME "upgrade" "skipping, already on version $TO"
        teardown $OCM_NAME $CD_NAMESPACE $CD_NAME
        return
    fi

    if [ "$OCP_CURRENT_VERSION" != "" ] && [ "$OCP_CURRENT_VERSION" != "$FROM" ] && [ "$KUBELET_VERSION_COUNT" == "1" ];
    then
        log $OCM_NAME "upgrade" "skipping, expect version $FROM, found version $OCP_CURRENT_VERSION"
        return
    fi

    # is the desired version supported?
    ALLOWED_UPDATE=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusterversion version -o json | jq ".status.availableUpdates[] | select(.force == false and .version == \"$TO\")")
    if [ "$ALLOWED_UPDATE" == "" ];
    then
        VERSION_CANDIDATES=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusterversion version -o json | jq ".status.availableUpdates | map(.version) | join(\", \")")
        log $OCM_NAME $LOG_NAME "Cannot upgrade from $FROM, it is not available in upgrade graph."
        log $OCM_NAME $LOG_NAME "Candidate versions are: $VERSION_CANDIDATES"
        teardown $OCM_NAME $CD_NAMESPACE $CD_NAME
        return
    fi

    # is upgrade already progressing?
    DESIRED_VERSION=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusterversion version -o jsonpath='{.spec.desiredUpdate.version}')

    if [ "$DESIRED_VERSION" != "$TO" ];
    then
        # desired version isn't set, to setup and patch clusterversion to kick off the upgrade
        setup $OCM_NAME $CD_NAMESPACE $CD_NAME

        log $OCM_NAME "upgrade" "upgrading from $FROM to $TO"

        CHANNEL_NAME=$(get_channel $TO)

        # https://issues.redhat.com/browse/OSD-3442
        KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc patch clusterversion version --type merge -p "{\"spec\":{\"overrides\": null}}"

        KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc patch clusterversion version --type merge -p "{\"spec\":{\"channel\": \"$CHANNEL_NAME\"}}"
        KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc patch clusterversion version --type merge -p "{\"spec\":{\"desiredUpdate\": {\"version\": \"$TO\"}}}"
    fi

    # 3. wait for upgrade to complete
    log $OCM_NAME "upgrade" "waiting for cluster version"
    OCP_CURRENT_VERSION=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusterversion version -o json | jq -r '.status.history[] | select(.verified == true and .state == "Completed") | .version' | grep $TO)
    
    while [ "$OCP_CURRENT_VERSION" != "$TO" ];
    do
        # print current CVO status (else it's very quiet output)
        CO_JSON=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusteroperator -o json)
        CO_COUNT=$(echo "$CO_JSON" | jq -r '.items | length')
        DEGRADED_COUNT=$(echo "$CO_JSON" | jq -r '.items[] | .metadata.name as $name | .status.conditions[] | select(.status == "True" and .type == "Degraded") | $name' | wc -l)
        PROGRESSING_COUNT=$(echo "$CO_JSON" | jq -r '.items[] | .metadata.name as $name | .status.conditions[] | select(.status == "True" and .type == "Progressing") | $name' | wc -l)

        CO_COUNT_TO=$(echo "$CO_JSON" | jq -r '.items[].status.versions[] | select(.name == "operator") | .version' | grep $TO | wc -l)

        # do not print status if there's nothing to print (i.e. the get failed for some reason)        
        if [ $CO_COUNT -gt 0 ];
        then
            log $OCM_NAME "upgrade" "ClusterOperators: Progressing: $PROGRESSING_COUNT, Degraded: $DEGRADED_COUNT, Upgraded: $CO_COUNT_TO/$CO_COUNT"
        fi

        # check status if we are not at the same version
        check_cluster_status $OCM_NAME $CD_NAMESPACE $CD_NAME "upgrade"

        # wait a (relatively) short time before checking version (and status when we look back through, if we do)
        sleep 60
        OCP_CURRENT_VERSION=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusterversion version -o json | jq -r '.status.history[] | select(.verified == true and .state == "Completed") | .version' | grep $TO)
    done

    log $OCM_NAME "upgrade" "ClusterVersion on $TO"
    log $OCM_NAME "upgrade" "checking node versions"

    # fun fact!  after clusterversion says it is done, individual nodes could still be updated.
    MACHINE_COUNT_ALL=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get nodes --no-headers | wc -l)

    MACHINE_COUNT_UPGRADED=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get nodes -o json | jq -r ".items[].status | select(.annotations[\"machineconfiguration.openshift.io/currentConfig\"] == .annotations[\"machineconfiguration.openshift.io/desiredConfig\"]) | .conditions[] | select(.type == \"Ready\" and .status == \"True\") | .reason" | wc -l)

    MACHINE_COUNT_PENDING=$((MACHINE_COUNT_ALL-MACHINE_COUNT_UPGRADED))

    # start maintenance only if we need to
    if [ ! $MACHINE_COUNT_UPGRADED -ge $MACHINE_COUNT_ALL ];
    then
        # Create a new maintenance window for the kubelet (non master) upgrades based on the number of nodes.
        MAINT_WINDOW_MIN=$((MACHINE_COUNT_PENDING*PD_MAINT_ADDITIONAL_NODE_MIN))

        # create worker maintenance window
        setup_maintenance_window $OCM_NAME $CD_NAMESPACE $CD_NAME $MAINT_WINDOW_MIN "$PD_MAINT_DESCRIPTION_WORKERS"

        # close control plane maintenance window
        teardown_maintenance_window $OCM_NAME $CD_NAMESPACE $CD_NAME "$PD_MAINT_DESCRIPTION_BASE"
    fi

    # log current state
    log $OCM_NAME "upgrade" "nodes upgraded: $MACHINE_COUNT_UPGRADED/$MACHINE_COUNT_ALL"

    # make sure all nodes run same kubelet version
    while [ $MACHINE_COUNT_UPGRADED -lt $MACHINE_COUNT_ALL ];
    do
        # sleep at beginning because we've already checked that we are not done.
        SLEEP_DURATION="$((PD_MAINT_ADDITIONAL_NODE_MIN*60/4))s"
        sleep "$SLEEP_DURATION"

        MACHINE_COUNT_UPGRADED=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get nodes -o json | jq -r ".items[].status | select(.annotations[\"machineconfiguration.openshift.io/currentConfig\"] == .annotations[\"machineconfiguration.openshift.io/desiredConfig\"]) | .conditions[] | select(.type == \"Ready\" and .status == \"True\") | .reason" | wc -l)

        MACHINE_COUNT_PENDING=$((MACHINE_COUNT_ALL-MACHINE_COUNT_UPGRADED))

        # and log current state
        log $OCM_NAME "upgrade" "nodes upgraded: $MACHINE_COUNT_UPGRADED/$MACHINE_COUNT_ALL"
    done

    log $OCM_NAME "upgrade" "all nodes on same version"

    # 4.3.0 - Delete ingress-operator and cluster-autoscaler-operator Deployments
    if [ "${TO}" == "4.3.0" ];
    then
        KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-ingress-operator delete deployment ingress-operator
        log $OCM_NAME "upgrade" "deleted openshift-ingress-operator/deployment/ingress-operator"
        KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-machine-api delete deployment cluster-autoscaler-operator
        log $OCM_NAME "upgrade" "deleted openshift-machine-api/deployment/cluster-autoscaler-operator"
    fi

    log $OCM_NAME "upgrade" "checking availability of ReplicaSets and DaemonSets"

    # verify all replicasets are at expected counts
    while true;
    do
        TOTAL_DESIRED=0
        for DESIRED in $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get replicasets --all-namespaces -o json | jq -r '.items[] | select(.metadata.namespace | startswith("default") or startswith("kube") or startswith("openshift")) | select(.status.replicas > 0) | .status.replicas');
        do
            TOTAL_DESIRED=$((TOTAL_DESIRED+DESIRED))
        done
        
        TOTAL_SCHEDULED=0
        for READY in $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get replicasets --all-namespaces -o json | jq -r '.items[] | select(.metadata.namespace | startswith("default") or startswith("kube") or startswith("openshift")) | select(.status.replicas > 0) | select(.status.replicas == .status.readyReplicas) | select(.status.replicas == .status.availableReplicas) | .status.replicas');
        do
            TOTAL_SCHEDULED=$((TOTAL_SCHEDULED+READY))
        done
        
        # output status
        log $OCM_NAME "upgrade" "ReplicaSets status: $TOTAL_SCHEDULED/$TOTAL_DESIRED"

        if [ $TOTAL_DESIRED -eq 0 ] || [ $TOTAL_DESIRED -ne $TOTAL_SCHEDULED ];
        then
            sleep 15
        else
            break
        fi
    done

    # verify all daemonsets are at expected counts
    while true;
    do
        TOTAL_DESIRED=0
        for DESIRED in $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get daemonsets --all-namespaces -o json | jq -r '.items[] | select(.metadata.namespace | startswith("default") or startswith("kube") or startswith("openshift")) | select(.status.desiredNumberScheduled > 0) | .status.desiredNumberScheduled');
        do
            TOTAL_DESIRED=$((TOTAL_DESIRED+DESIRED))
        done
        
        TOTAL_SCHEDULED=0
        for READY in $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get daemonsets --all-namespaces -o json | jq -r '.items[] | select(.metadata.namespace | startswith("default") or startswith("kube") or startswith("openshift")) | select(.status.desiredNumberScheduled > 0) | select(.status.desiredNumberScheduled == .status.numberReady) | select(.status.desiredNumberScheduled == .status.numberAvailable) | .status.desiredNumberScheduled');
        do
            TOTAL_SCHEDULED=$((TOTAL_SCHEDULED+READY))
        done
        
        # output status
        log $OCM_NAME "upgrade" "DaemonSets status: $TOTAL_SCHEDULED/$TOTAL_DESIRED"

        if [ $TOTAL_DESIRED -eq 0 ] || [ $TOTAL_DESIRED -ne $TOTAL_SCHEDULED ];
        then
            sleep 15
        else
            break
        fi
    done

    log $OCM_NAME "upgrade" "all ReplicaSets and DaemonSets available"

    log $OCM_NAME "upgrade" "upgrade is complete"

    teardown $OCM_NAME $CD_NAMESPACE $CD_NAME
}

prepare_kubeconfig() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3

    if [ ! -f "${TMP_DIR}/kubeconfig-${CD_NAMESPACE}" ];
    then
        # https://issues.redhat.com/browse/OSD-3443 ==> change 'api' to 'rh-api'
        oc -n $CD_NAMESPACE extract "secret/$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.spec.clusterMetadata.adminKubeconfigSecretRef.name')" --keys=kubeconfig --to=- | sed 's#server: https://api\.#server: https://rh-api\.#g' > ${TMP_DIR}/kubeconfig-${CD_NAMESPACE}
    fi
}

check_cluster_status() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3
    LOG_NAME=$4

    prepare_kubeconfig $OCM_NAME $CD_NAMESPACE $CD_NAME

    CLUSTER_STATUS=1 # start with "good"

    # check several things about the cluster and report problems
    # * api availability
    # * critical alerts
    # * degraded operators (if there are critical alerts only)

    API_RESPONSE=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get --raw /api 2>&1)
    API_VERSION=$(echo $API_RESPONSE | jq -r '.versions[]' || echo "FAIL")

    if [ "$API_VERSION" == "v1" ];
    then
        OUTPUT="$OUTPUT,\"API=OK\""
    else
        log $OCM_NAME $LOG_NAME "INFO: API requests are failing, msg = $API_RESPONSE"
        # don't bother with other checks, there is a good chance they won't work
        CLUSTER_STATUS=0
        return
    fi

    # get a list of firing critical alerts in core namespaces (these would alert SREP in PD)
    # NOTE exclude ClusterUpgradingSRE and DNSErrors05MinSRE
    CA=$(curl -G -s -k -H "Authorization: Bearer $(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-monitoring sa get-token prometheus-k8s)" --data-urlencode "query=ALERTS{alertstate=\"firing\",severity=\"critical\",namespace=~\"^openshift.*|^kube.*|^default$\",alertname!=\"ClusterUpgradingSRE\",alertname!=\"DNSErrors05MinSRE\"}" "https://$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc -n openshift-monitoring get routes prometheus-k8s -o json | jq -r .spec.host)/api/v1/query" | jq -r '.data.result[].metric.alertname' | tr '\n' ',' )

    if [ "$CA" != "" ];
    then
        log $OCM_NAME $LOG_NAME "WARNING: Critical Alerts = $CA"
        CLUSTER_STATUS=0

        # degraded operators
        DCO=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusteroperator --no-headers | awk '{print $1 "," $5}' | grep -v ",False" | awk -F, '{print $1 ","}' | xargs)
        
        if [ "$DCO" != "" ];
        then
            log $OCM_NAME $LOG_NAME "INFO: Degraded Operators = $DCO"

            for CO in $DCO;
            do
                # get clusteroperator error if we can
                CO_MESSAGE=$(KUBECONFIG=$TMP_DIR/kubeconfig-${CD_NAMESPACE} oc get clusteroperator $CO -o json 2>/dev/null | jq -r '.status.extension.lastSyncError')

                if [ "$CO_MESSAGE" != "" ];
                then
                    log $OCM_NAME $LOG_NAME "INFO: Operator $CO lastSyncError = $CO_MESSAGE"
                fi
            done

        fi
    fi
}

teardown() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3

    prepare_kubeconfig $OCM_NAME $CD_NAMESPACE $CD_NAME

    ORIGINAL_REPLICAS=$(oc -n $CD_NAMESPACE get clusterdeployment $CD_NAME -o json | jq -r '.metadata.labels["managed.openshift.io/original-worker-replicas"] | select(. != null)' 2>/dev/null)
    DESIRED_REPLICAS=$(oc -n $CD_NAMESPACE get machinepool "$CD_NAME-worker" -o json | jq -r '.spec.replicas')

    if [ "$ORIGINAL_REPLICAS" != "" ] && [ "$ORIGINAL_REPLICAS" != "$DESIRED_REPLICAS" ];
    then
        # need to set replicas back to the original and clear the label
        oc -n $CD_NAMESPACE get machinepool "$CD_NAME-worker" -o json | jq -r ".spec.replicas=$ORIGINAL_REPLICAS" | oc replace -f -
        oc -n $CD_NAMESPACE label clusterdeployment $CD_NAME managed.openshift.io/original-worker-replicas-

        log $OCM_NAME "teardown" "dropping replicas back from $DESIRED_REPLICAS to $ORIGINAL_REPLICAS"
    fi

    # take down maintenance windows (both just to be sure they're all gone)
    teardown_maintenance_window $OCM_NAME $CD_NAMESPACE $CD_NAME "$PD_MAINT_DESCRIPTION_BASE"
    teardown_maintenance_window $OCM_NAME $CD_NAMESPACE $CD_NAME "$PD_MAINT_DESCRIPTION_WORKERS"

    # start with it "bad" to force a check, which will continue until it's good
    while [ true ];
    do
        check_cluster_status $OCM_NAME $CD_NAMESPACE $CD_NAME "teardown"
        if [ $CLUSTER_STATUS -eq 0 ];
        then
            log $OCM_NAME "teardown" "ERROR: cluster state needs fixed, see prior logs"
            # wait a bit so we give things a chance to change and not spam the api
            sleep 15
        else
            # things are healthy, we're done
            break
        fi
    done
}

teardown_maintenance_window() {
    OCM_NAME=$1
    CD_NAMESPACE=$2
    CD_NAME=$3
    MAINT_DESC=$4

    # stop maintenance in PagerDuty (if not in mainteance)
    PD_API_KEY=$(oc -n pagerduty-operator get secrets pagerduty-api-key -o json | jq -r '.data.PAGERDUTY_API_KEY' | base64 --decode)

    CD_DOMAIN=$(oc get clusterdeployment -n $CD_NAMESPACE $CD_NAME -o json | jq -r ".spec.baseDomain")

    # search PD with cluster FQDN (could be full serivce name, but that might change)
    CLUSTER_FQDN="$CD_NAME.$CD_DOMAIN"

    PD_SERVICE_ID=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/services?time_zone=UTC&sort_by=name&query=$CLUSTER_FQDN" | jq -r '.services[0].id')

    # sanity check the service ID is for the cluster
    PD_OK=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/services/$PD_SERVICE_ID" | grep $CD_NAME | wc -l)

    # if we didn't get the specific service we expect, skip mainteance
    # if we got null the service doesn't exist
    # if we got "" there is a configuration issue (nothing we can do)

    if [ $PD_OK > 0 ] && [ "$PD_SERVICE_ID" != "null" ] && [ "$PD_SERVICE_ID" != "" ];
    then
        # search for existing maintenance ID
        # IMPORTANT: description must match, else we might remove maintenance put in place for other reasons.
        PD_MAINT_ID=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/maintenance_windows?service_ids%5B%5D=$PD_SERVICE_ID&query=$(echo $MAINT_DESC | tr ' ' '+')&filter=open" | jq -r 'select(.maintenance_windows != null) | .maintenance_windows[0].id')

        # if we got null maintenance doesn't exist
        # if we got "" there is a configuration issue (nothing we can do)

        if [ "$PD_MAINT_ID" != "null" ] && [ "$PD_MAINT_ID" != "" ];
        then
            # stop maintenance for this cluster
            curl --max-time 10 -s -X DELETE -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/maintenance_windows/$PD_MAINT_ID"

            # make sure it was ended / deleted
            sleep 5 # give it a while to apply

            PD_MAINT_ID=$(curl --max-time 10 -s -X GET -H 'Accept: application/vnd.pagerduty+json;version=2' -H "Authorization: Token token=$PD_API_KEY" "https://api.pagerduty.com/maintenance_windows?service_ids%5B%5D=$PD_SERVICE_ID&query=$(echo $MAINT_DESC | tr ' ' '+')&filter=open" | jq -r 'select(.maintenance_windows != null) | .maintenance_windows[0].id')

            if [ "$PD_MAINT_ID" == "null" ] || [ "$PD_MAINT_ID" == "" ];
            then
                log $OCM_NAME "teardown" "INFO: maintenance ended = '$MAINT_DESC'"
            else
                log $OCM_NAME "teardown" "WARNING: maintenance failed to end = '$MAINT_DESC'"
            fi
        else
            log $OCM_NAME "teardown" "INFO: maintenance doesn't exist, not ending = '$MAINT_DESC'"
        fi
    else
        log $OCM_NAME "teardown" "WARNING: maintenance failed to end, no service exists = '$MAINT_DESC'"
    fi

    unset PD_API_KEY
}

get_channel() {
    VERSION=$1

    VERSION_MINOR=$(echo "${VERSION}" | sed 's/\([^.]*\.[^.]*\)\..*/\1/g')
    
    CHANNEL_NAME="stable-$VERSION_MINOR"

    echo $CHANNEL_NAME
}

# Verify we have ClusterDeployment CRs to work with
if [ $(oc get crd clusterdeployments.hive.openshift.io --no-headers 2>/dev/null | wc -l) == "0" ];
then
    echo "ERROR: Current cluster does not have Hive installed.  Verify where you are logged in."
    exit 1
fi

if [[ -n $OCP_VERSION_TO ]];
then
    # Verify the target version exists as a ClusterImageSet (CIS) on the cluster
    # (if not, the customer could never install to that target version)
    CIS_VERSION=$(oc get clusterimageset -o json | jq -r ".items[].metadata.name | split(\"v\")[1] | select(. == \"$OCP_VERSION_TO\")")
    if [ "$OCP_VERSION_TO" != "$CIS_VERSION" ];
    then
        echo "Cannot upgrade to $OCP_VERSION_TO, it is not available as a ClusterImageSet in the cluster."
        exit 3
    fi

    # If the image isn't even enabled, we certainly can't upgrade to it. But if it is enabled, we're going there anyways.
    CIS_ENABLED=$(oc get clusterimageset --all-namespaces -l api.openshift.com/enabled=true -o json | jq -r ".items[].metadata.name | split(\"v\")[1] | select(. == \"$OCP_VERSION_TO\")")
    if [ -z "$CIS_ENABLED" ];
    then
        echo "Cannot upgrade to $OCP_VERSION_TO, it is not currently 'enabled'."
        exit 4
    fi

    TARGET_IMAGE=$(oc get clusterimageset --all-namespaces openshift-v$OCP_VERSION_TO -o json | jq -r ".spec.releaseImage | split(\":\")[1]")

    # Verify the target version is greater than the "from" version
    if ! vercomp "${OCP_VERSION_FROM}" "${TARGET_IMAGE}";
    then
        echo "Cannot upgrade to ClusterImageSet $TARGET_IMAGE because it is not greater than $OCP_VERSION_FROM"
        exit 5
    fi
fi

for CD_NAMESPACE in $(oc get clusterdeployment --all-namespaces | awk '{print $1}' | sort | uniq);
do  
    for CD_NAME in $(oc -n $CD_NAMESPACE get clusterdeployment -o json | jq -r '.items[] | select(.metadata.labels["api.openshift.com/managed"] == "true") | select(.metadata.deletionTimestamp == null or .metadata.deletionTimestamp == "") | select(.spec.installed == true) | select(.status.clusterVersionStatus.history[0].state == "Completed") | .metadata.name');
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
