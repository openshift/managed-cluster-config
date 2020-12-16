#!/bin/bash

function test_clean {
    # cleanup
    oc -n openshift-logging delete job osd-logging-freeze-test
    oc -n openshift-logging delete job osd-logging-unfreeze-test
    oc -n openshift-logging delete cm osd-logging-freeze
    oc delete -f 01-cronjob.yaml
    oc -n openshift-logging delete subscription cluster-logging
    oc -n openshift-logging delete subscription elasticsearch-operator
    oc -n openshift-logging delete $(oc -n openshift-logging get csv -o name | grep -e clusterlogging -e elasticsearch) || true

    # wait for pods to terminate, ensures a clean state
    while [ "$(oc -n openshift-logging get pods -l job-name=osd-logging-freeze-test --no-headers | wc -l)" != "0" ];
    do
        sleep 1
    done

    while [ "$(oc -n openshift-logging get pods -l job-name=osd-logging-unfreeze-test --no-headers | wc -l)" != "0" ];
    do
        sleep 1
    done
}

function test_subscriptions {
    APPROVAL_VALUE=$1

    cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
    name: cluster-logging
    namespace: openshift-logging
spec:
    channel: '4.4'
    installPlanApproval: $APPROVAL_VALUE
    name: cluster-logging
    source: redhat-operators
    sourceNamespace: openshift-marketplace
EOF

    cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
    name: elasticsearch-operator
    namespace: openshift-logging
spec:
    channel: '4.4'
    installPlanApproval: $APPROVAL_VALUE
    name: elasticsearch-operator
    source: redhat-operators
    sourceNamespace: openshift-marketplace
EOF

}

function test_execute_freeze {
    # delete old job
    oc -n openshift-logging delete job osd-logging-freeze-test 2>/dev/null
    # wait for pods to terminate, ensures a clean state
    while [ "$(oc -n openshift-logging get pods -l job-name=osd-logging-freeze-test --no-headers | wc -l)" != "0" ];
    do
        sleep 1
    done

    # configure the job
    oc -n openshift-logging delete cm osd-logging-freeze 2>/dev/null
    oc -n openshift-logging create cm osd-logging-freeze --from-literal annotation=oldInstallPlanApproval --from-literal freeze="true"

    # create the job etc
    oc apply -f 01-cronjob.yaml 2>/dev/null

    # run the job
    oc -n openshift-logging create job osd-logging-freeze-test --from=cronjob/osd-logging-freeze

    # wait for pod to start..
    while [ "$(oc -n openshift-logging get pods -l job-name=osd-logging-freeze-test --no-headers | grep Running | wc -l)" == "0" ];
    do
        sleep 1
        oc -n openshift-logging get pods -l job-name=osd-logging-freeze-test --no-headers
    done

    # wait for job pod to complete (and tail the logs)
    oc -n openshift-logging logs $(oc -n openshift-logging get pod -l job-name=osd-logging-freeze-test -o name) -f
}

function test_verify {
    CONTEXT=$1
    SUBSCRIPTION_VALUE=$2
    ANNOATATION_VALUE=$3
    # check state
    for SUBSCRIPTION in $(oc -n openshift-logging get subscriptions -o name);
    do
        ACTUAL_VALUE=$(oc -n openshift-logging get $SUBSCRIPTION -o jsonpath='{.spec.installPlanApproval}')
        if [ "$SUBSCRIPTION_VALUE" != "$ACTUAL_VALUE" ];
        then
            echo "FAILURE: $CONTEXT, $SUBSCRIPTION .spec.installPlanApproval, expected=$SUBSCRIPTION_VALUE, found=$ACTUAL_VALUE"
        fi

        ACTUAL_VALUE=$(oc -n openshift-logging get $SUBSCRIPTION -o jsonpath='{.metadata.annotations.oldInstallPlanApproval}')
        if [ "$ANNOATATION_VALUE" != "$ACTUAL_VALUE" ];
        then
            echo "FAILURE: $CONTEXT, $SUBSCRIPTION .metadata.annotations.oldInstallPlanApproval, expected=$ANNOATATION_VALUE, found=$ACTUAL_VALUE"
        fi
    done
}

function test_execute_unfreeze {
    # delete old job
    oc -n openshift-logging delete job osd-logging-unfreeze-test 2>/dev/null
    # wait for pods to terminate, ensures a clean state
    while [ "$(oc -n openshift-logging get pods -l job-name=osd-logging-unfreeze-test --no-headers | wc -l)" != "0" ];
    do
        sleep 1
    done

    # update configuration
    oc -n openshift-logging delete cm osd-logging-freeze 
    oc -n openshift-logging create cm osd-logging-freeze --from-literal annotation=oldInstallPlanApproval --from-literal freeze="false"

    # run the job
    oc -n openshift-logging create job osd-logging-unfreeze-test --from=cronjob/osd-logging-freeze

    # wait for pod to start..
    while [ "$(oc -n openshift-logging get pods -l job-name=osd-logging-unfreeze-test --no-headers | grep Running | wc -l)" == "0" ];
    do
        sleep 1
        oc -n openshift-logging get pods -l job-name=osd-logging-unfreeze-test --no-headers
    done

    # wait for job pod to complete (and tail the logs)
    oc -n openshift-logging logs $(oc -n openshift-logging get pod -l job-name=osd-logging-unfreeze-test -o name) -f
}

function test0 {
    echo "=========== No Subscriptions ============"

    echo -n "INFO: Testing freeze.."
    test_execute_freeze 1>&2
    echo "done"

    test_verify "freeze" "" ""

    echo -n "INFO: Testing unfreeze.."
    test_execute_unfreeze 1>&2
    echo "done"

    test_verify "unfreeze" "" ""

    echo -n "INFO: Cleaning up after test..."
    test_clean >/dev/null 2>/dev/null
    echo "done"

    echo "========================================"
}

function test1 {
    echo "=========== Start Automatic ============"

    echo -n "INFO: Creating subscriptions..."
    test_subscriptions "Automatic" 1>&2
    echo "done"

    echo -n "INFO: Testing freeze.."
    test_execute_freeze 1>&2
    echo "done"

    test_verify "freeze" "Manual" "Automatic"

    echo -n "INFO: Testing unfreeze.."
    test_execute_unfreeze 1>&2
    echo "done"

    test_verify "unfreeze" "Automatic" ""

    echo -n "INFO: Cleaning up after test..."
    test_clean >/dev/null 2>/dev/null
    echo "done"

    echo "========================================"
}

function test2 {
    echo "=========== Start Manual ==============="

    echo -n "INFO: Creating subscriptions..."
    test_subscriptions "Manual" 1>&2
    echo "done"

    echo -n "INFO: Testing freeze.."
    test_execute_freeze 1>&2
    echo "done"

    test_verify "freeze" "Manual" ""

    echo -n "INFO: Testing unfreeze.."
    test_execute_unfreeze 1>&2
    echo "done"

    test_verify "unfreeze" "Manual" ""

    echo -n "INFO: Cleaning up after test..."
    test_clean >/dev/null 2>/dev/null
    echo "done"

    echo "========================================"
}

function test3 {
    echo "== Start Automatic, Customer Unfreeze =="

    echo -n "INFO: Creating subscriptions..."
    test_subscriptions "Automatic" 1>&2
    echo "done"

    echo -n "INFO: Testing freeze.."
    test_execute_freeze 1>&2
    echo "done"

    test_verify "freeze" "Manual" "Automatic"

    echo -n "INFO: 'Customer' update to Automatic..."
    test_subscriptions "Automatic" 1>&2
    echo "done"

    echo -n "INFO: Testing freeze (overriden).."
    test_execute_freeze 1>&2
    echo "done"

    test_verify "freeze" "Automatic" "Automatic"

    echo -n "INFO: Testing unfreeze.."
    test_execute_unfreeze 1>&2
    echo "done"

    test_verify "unfreeze" "Automatic" ""

    echo -n "INFO: Cleaning up after test..."
    test_clean >/dev/null 2>/dev/null
    echo "done"

    echo "========================================"
}

echo -n "INFO: Cleaning up prior test state..."
test_clean >/dev/null 2>/dev/null
echo "done"

test0

test1

test2

test3

# in case this put anything in the background, wait..
wait