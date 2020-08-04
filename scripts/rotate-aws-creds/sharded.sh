#!/bin/bash
set -euo pipefail

source "$(dirname $0)/common.sh"

SHARD_SSH="ssh root@hive-production-master"
OC_CMD="oc --insecure-skip-tls-verify=true"

fixup_kubeconfig() {
    sed -i 's#https://api.#https://rh-api.#' "$1"
}

cleanup() {
    rm -f "$SHARD_KUBECONFIG"
    rm -f "$CLUSTER_KUBECONFIG"
    rm -r "$CREDREQ_DIR"
}

update_aws_secret() {
    local KUBECONFIG=$1
    local SECRET_NAMESPACE=$2
    local SECRET_NAME=$3
    # assumes encoded vars are set already by iam_user_create_accesskey

    KUBECONFIG=$KUBECONFIG $OC_CMD get secret -n "$SECRET_NAMESPACE" "$SECRET_NAME" -o json | jq -r ".data.aws_access_key_id = \"$ENCODED_ACCESS_KEY_ID\" | .data.aws_secret_access_key = \"$ENCODED_SECRET_ACCESS_KEY\"" | KUBECONFIG=$KUBECONFIG $OC_CMD replace -f -
}

CLUSTER_NAME=${1:-}
SHARD_NAME=${2:-}
if [[ $CLUSTER_NAME == "" || $SHARD_NAME == "" ]]; then
    echo "Usage: $0 CLUSTER_NAME SHARD_NAME"
    exit 1
fi

CLUSTER_ID=$(ocm list clusters | grep "$CLUSTER_NAME" | awk '{print $1}')

SHARD_KUBECONFIG=$(mktemp /tmp/kubeconfig.XXXXXXX)
CLUSTER_KUBECONFIG=$(mktemp /tmp/kubeconfig.XXXXXXX)
CREDREQ_DIR=$(mktemp -d)
trap cleanup exit 

SHARD_NAMESPACE=$(${SHARD_SSH} oc get accountclaims --all-namespaces | grep "${SHARD_NAME}" | awk '{print $1}')
SHARD_KUBECONFIG_SECRET=$(${SHARD_SSH} oc get secret -n "${SHARD_NAMESPACE}" | grep kubeconfig | awk '{print $1}')
${SHARD_SSH} "oc get secret -n ${SHARD_NAMESPACE} ${SHARD_KUBECONFIG_SECRET} -o json" | jq -r '.data["raw-kubeconfig"]' | base64 -d >"$SHARD_KUBECONFIG"
fixup_kubeconfig "$SHARD_KUBECONFIG"

CLUSTER_NAMESPACE=$(KUBECONFIG=${SHARD_KUBECONFIG} ${OC_CMD} get accountclaims --all-namespaces | grep "${CLUSTER_ID}" | awk '{print $1}')
CLUSTER_KUBECONFIG_SECRET=$(KUBECONFIG=${SHARD_KUBECONFIG} ${OC_CMD} get secret -n "${CLUSTER_NAMESPACE}" | grep kubeconfig | awk '{print $1}')
KUBECONFIG="${SHARD_KUBECONFIG}" ${OC_CMD} get secret -n "${CLUSTER_NAMESPACE}" "${CLUSTER_KUBECONFIG_SECRET}" -o json | jq -r '.data["raw-kubeconfig"]' | base64 -d >"$CLUSTER_KUBECONFIG"
fixup_kubeconfig "$CLUSTER_KUBECONFIG"

CCS_ANNOTATION=$(KUBECONFIG="${SHARD_KUBECONFIG}" ${OC_CMD} get clusterdeployment -n "$CLUSTER_NAMESPACE" "$CLUSTER_NAME" -o json | jq -r '.metadata.labels["api.openshift.com/ccs"]')
if [[ "$CCS_ANNOTATION" == "true" ]]; then
    CCS_CLUSTER="1"
    CREDENTIALS_SECRET_NAME="byoc"
else
    CCS_CLUSTER="0"
    CREDENTIALS_SECRET_NAME="aws"
fi

ACCESS_KEY_ID=$(KUBECONFIG="$SHARD_KUBECONFIG" $OC_CMD get secrets -n "$CLUSTER_NAMESPACE" $CREDENTIALS_SECRET_NAME -o json | jq -r '.data.aws_access_key_id' | base64 --decode)
SECRET_ACCESS_KEY=$(KUBECONFIG="$SHARD_KUBECONFIG" $OC_CMD get secrets -n "$CLUSTER_NAMESPACE" $CREDENTIALS_SECRET_NAME -o json | jq -r '.data.aws_secret_access_key' | base64 --decode)
AWS_PROFILE=$CLUSTER_ID
aws_cli_setup "$ACCESS_KEY_ID" "$SECRET_ACCESS_KEY" "$AWS_PROFILE"
info "Retrived original AccessKey."

aws_iam_username "osdManagedAdmin"

######################################
### Create new credentials for osdManagedAdmin

iam_user_create_accesskey "$KEY_USERNAME"

# switch to new profile so we can delete the old one
AWS_PROFILE=$CLUSTER_ID-new

######################################
### Changes on the hive cluster

# Replace aws-account-operator secret
SECRET_NAME=$(KUBECONFIG=$SHARD_KUBECONFIG $OC_CMD -n "$CLUSTER_NAMESPACE" get accountclaim -o jsonpath='{.items[].spec.accountLink}')-secret
update_aws_secret "$SHARD_KUBECONFIG" aws-account-operator "$SECRET_NAME"

info "Replaced AWS Account Operator Secret."

# Replace aws secret (in cluster's hive namespace)
update_aws_secret "$SHARD_KUBECONFIG" "$CLUSTER_NAMESPACE" $CREDENTIALS_SECRET_NAME

info "Replaced Hive AWS Secret."

######################################
### Delete old credentials for osdManagedAdmin

iam_user_delete_accesskey "$KEY_USERNAME" "$ACCESS_KEY_ID"

######################################
### Changes on the OSD cluster

update_aws_secret "$CLUSTER_KUBECONFIG" kube-system aws-creds

info "Replaced OSD kube-system aws-creds Secret."

# restart cloud-credential-operator pod, make sure it has the updated secret
CCO_POD=$(KUBECONFIG=$CLUSTER_KUBECONFIG $OC_CMD -n openshift-cloud-credential-operator get pods | grep cloud-credential-operator | awk '{print $1}')
KUBECONFIG=$CLUSTER_KUBECONFIG $OC_CMD -n openshift-cloud-credential-operator delete pod "$CCO_POD"

rotate_credential_requests "$CREDREQ_DIR" "$CLUSTER_KUBECONFIG" "$OC_CMD"

######################################
### Rotate SRE IAM User Credentials

SRE_SECRET_NAME=$(KUBECONFIG=$SHARD_KUBECONFIG $OC_CMD -n "$CLUSTER_NAMESPACE" get accountclaim -o jsonpath='{.items[].spec.accountLink}')-osdmanagedadminsre-secret
ACCESS_KEY_ID=$(KUBECONFIG=$SHARD_KUBECONFIG $OC_CMD get secrets -n aws-account-operator "$SRE_SECRET_NAME" -o json | jq -r '.data.aws_access_key_id' | base64 --decode)
SECRET_ACCESS_KEY=$(KUBECONFIG=$SHARD_KUBECONFIG $OC_CMD get secrets -n aws-account-operator "$SRE_SECRET_NAME" -o json | jq -r '.data.aws_secret_access_key' | base64 --decode)
AWS_PROFILE=$CLUSTER_ID-sre
aws_cli_setup "$ACCESS_KEY_ID" "$SECRET_ACCESS_KEY" "$AWS_PROFILE"

aws_iam_username "osdManagedAdminSRE"
iam_user_create_accesskey "$KEY_USERNAME"
update_aws_secret "$SHARD_KUBECONFIG" aws-account-operator "$SRE_SECRET_NAME"
iam_user_delete_accesskey "$KEY_USERNAME" "$OLD_ACCESS_KEY_ID"

info "Rotated SRE IAM User credentials."

######################################
### Wipe AWS Profile data

# can't find a clean cli option to remove them, so will simply set with junk
aws_cli_setup "X" "X" "$CLUSTER_ID"
aws_cli_setup "X" "X" "$CLUSTER_ID-new"
aws_cli_setup "X" "X" "$CLUSTER_ID-sre"
aws_cli_setup "X" "X" "$CLUSTER_ID-sre-new"

info "Done!"
