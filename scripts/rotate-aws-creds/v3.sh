#!/bin/bash

source "$(dirname $0)/common.sh"

ENVIRONMENT=$1
CLUSTER_ID=$2

# make sure we have no state for the aws cli
unset AWS_PROFILE
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
# Region is a mandatory value to be set when using AWS CLI.
# All AWS CLI requests are related to IAM and are global, so picking any region will be OK.
export AWS_DEFAULT_REGION=us-east-1

if [ "${CLUSTER_ID}" == "" ] || [ "${ENVIRONMENT}" == "" ];
then
    echo "usage: $0 <environment> <cluster id>"
    echo "example: $0 stage 18kshg9idnn687p1bstlh669hlod7ldr"
    exit 1
fi

update_aws_secret() {
    SECRET_NAMESPACE=$1
    SECRET_NAME=$2
    # assumes encoded vars are set already by iam_user_create_accesskey

    ssh "root@hive-${ENVIRONMENT}-master" "oc get secret -n ${SECRET_NAMESPACE} ${SECRET_NAME} -o json | jq -r \".data.aws_access_key_id = \\\"${ENCODED_ACCESS_KEY_ID}\\\" | .data.aws_secret_access_key = \\\"${ENCODED_SECRET_ACCESS_KEY}\\\"\" | oc replace -f -"
}

NAMESPACE=$(ssh "root@hive-${ENVIRONMENT}-master" "oc get clusterdeployment --all-namespaces --no-headers | grep \"${CLUSTER_ID} \" | awk '{print \$1}'")
CLUSTER_NAME=$(ssh "root@hive-${ENVIRONMENT}-master" "oc get clusterdeployment --all-namespaces --no-headers | grep \"${CLUSTER_ID} \" | awk '{print \$2}'")

if [ "$(ssh "root@hive-${ENVIRONMENT}-master" "oc get clusterdeployment -n ${NAMESPACE} ${CLUSTER_NAME} -o json" | jq -r '.metadata.labels["api.openshift.com/ccs"]')" == "true" ]; then
    CCS_CLUSTER="1"
else
    CCS_CLUSTER="0"
fi

ACCESS_KEY_ID=$(ssh "root@hive-${ENVIRONMENT}-master" "oc get secrets -n ${NAMESPACE} aws -o json | jq -r '.data.aws_access_key_id' | base64 -d")
SECRET_ACCESS_KEY=$(ssh "root@hive-${ENVIRONMENT}-master" "oc get secrets -n ${NAMESPACE} aws -o json | jq -r '.data.aws_secret_access_key' | base64 -d")
AWS_PROFILE=${ENVIRONMENT}-${CLUSTER_ID}
aws_cli_setup "${ACCESS_KEY_ID}" "${SECRET_ACCESS_KEY}" "${AWS_PROFILE}"
info "Retrived original AccessKey."

aws_iam_username "osdManagedAdmin"

######################################
### Create new credentials for osdManagedAdmin

iam_user_create_accesskey "${KEY_USERNAME}"

# switch to new profile so we can delete the old one
AWS_PROFILE=${ENVIRONMENT}-${CLUSTER_ID}-new

######################################
### Changes on the hive cluster

# Replace aws-account-operator secret
SECRET_NAME=$(ssh "root@hive-${ENVIRONMENT}-master" "oc -n ${NAMESPACE} get accountclaim -o jsonpath='{.items[].spec.accountLink}'")-secret
update_aws_secret aws-account-operator "${SECRET_NAME}"

info "Replaced AWS Account Operator Secret."

# Replace aws secret (in cluster's hive namespace)
update_aws_secret "${NAMESPACE}" aws 

# If CCS cluster also update the "byoc" secret
if [[ "$CCS_CLUSTER" == "1" ]]; then 
    update_aws_secret "$NAMESPACE" "byoc"
fi

info "Replaced Hive AWS Secret."

######################################
### Delete old credentials for osdManagedAdmin

iam_user_delete_accesskey "${KEY_USERNAME}" "${ACCESS_KEY_ID}"

######################################
### Changes on the OSD cluster

# Get kubeconfig
TEMP_DIR=$(mktemp -d)
ssh "root@hive-${ENVIRONMENT}-master" "oc -n ${NAMESPACE} extract \"\$(oc -n ${NAMESPACE} get secrets -o name | grep kubeconfig)\" --keys=kubeconfig --to=-" > "${TEMP_DIR}/kubeconfig-${NAMESPACE}"

# Update kube-system aws-creds secret (main secret used to mint other credentials)
KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n kube-system get secret aws-creds -o json | jq -r ".data.aws_access_key_id = \"${ENCODED_ACCESS_KEY_ID}\" | .data.aws_secret_access_key = \"${ENCODED_SECRET_ACCESS_KEY}\"" | KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc replace -f -

info "Replaced OSD kube-system aws-creds Secret."

# restart cloud-credential-operator pod, make sure it has the updated secret
CCO_POD=$(KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n openshift-cloud-credential-operator get pods | grep cloud-credential-operator | awk '{print $1}')
KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n openshift-cloud-credential-operator delete pod "${CCO_POD}"

# Rotate CVO managed credentials (simply delete them)
for CR in $(KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc get credentialsrequests -n openshift-cloud-credential-operator -o json | jq -r '.items[].metadata.name');
do
    KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n openshift-cloud-credential-operator delete credentialsrequest "${CR}"
done

info "Rotated CVO managed CredentialsRequests."

rotate_credential_requests "${TEMP_DIR}" "${TEMP_DIR}/kubeconfig-${NAMESPACE}" "oc"
# NOTE do not wait for pod deletion.

######################################
### Rotate SRE IAM User Credentials
SECRET_NAME=$(ssh "root@hive-${ENVIRONMENT}-master" "oc -n ${NAMESPACE} get accountclaim -o jsonpath='{.items[].spec.accountLink}'")-osdmanagedadminsre-secret
ACCESS_KEY_ID=$(ssh "root@hive-${ENVIRONMENT}-master" "oc get secrets -n aws-account-operator ${SECRET_NAME} -o json | jq -r '.data.aws_access_key_id' | base64 -d")
SECRET_ACCESS_KEY=$(ssh "root@hive-${ENVIRONMENT}-master" "oc get secrets -n aws-account-operator ${SECRET_NAME} -o json | jq -r '.data.aws_secret_access_key' | base64 -d")
AWS_PROFILE=${ENVIRONMENT}-${CLUSTER_ID}-sre
aws_cli_setup "${ACCESS_KEY_ID}" "${SECRET_ACCESS_KEY}" "${AWS_PROFILE}"

aws_iam_username "osdManagedAdminSRE"
iam_user_create_accesskey "${KEY_USERNAME}"
update_aws_secret aws-account-operator "${SECRET_NAME}"
iam_user_delete_accesskey "${KEY_USERNAME}" "${OLD_ACCESS_KEY_ID}"

info "Rotated SRE IAM User credentials."

######################################
### Wipe AWS Profile data

# can't find a clean cli option to remove them, so will simply set with junk
aws_cli_setup "X" "X" "${ENVIRONMENT}-${CLUSTER_ID}"
aws_cli_setup "X" "X" "${ENVIRONMENT}-${CLUSTER_ID}-new"
aws_cli_setup "X" "X" "${ENVIRONMENT}-${CLUSTER_ID}-sre"
aws_cli_setup "X" "X" "${ENVIRONMENT}-${CLUSTER_ID}-sre-new"

info "Done!"
