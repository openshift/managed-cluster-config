#!/bin/bash

ENVIRONMENT=$1
CLUSTER_ID=$2

# make sure we have no state for the aws cli
unset AWS_PROFILE
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=us-east-1

if [ "$CLUSTER_ID" == "" ] || [ "$ENVIRONMENT" == "" ];
then
    echo "usage: $0 <environment> <cluster id>"
    echo "example: $0 stage 18kshg9idnn687p1bstlh669hlod7ldr"
    exit 1
fi

info() {
    echo "INFO: $1"
}

aws_cli_setup() {
    KEY_ID=$1
    SECRET_KEY=$2
    PROFILE_NAME=$3

    info "Using access key '$KEY_ID'."

    echo -e "${KEY_ID}\n${SECRET_KEY}\nus-east-1\njson\n" | aws configure --profile $PROFILE_NAME 2>/dev/null >/dev/null
}

iam_user_create_accesskey() {
    AWS_USERNAME=$1

    info "IAM User: $AWS_USERNAME"

    ORIG_ACCOUNTID=$(AWS_PROFILE=$AWS_PROFILE aws sts get-caller-identity | jq -r '.Account')

    info "Account ID: $ORIG_ACCOUNTID"

    # create a new access key
    ACCESS_KEY_JSON=$(AWS_PROFILE=$AWS_PROFILE aws iam create-access-key --user-name $AWS_USERNAME)

    # get encoded access key data
    NEW_ACCESS_KEY_ID=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.AccessKeyId' | tr -d '\n')
    ENCODED_ACCESS_KEY_ID=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.AccessKeyId' | tr -d '\n' | base64)
    NEW_SECRET_ACCESS_KEY=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.SecretAccessKey' | tr -d '\n')
    ENCODED_SECRET_ACCESS_KEY=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.SecretAccessKey' | tr -d '\n' | base64)

    info "Created new AccessKey for IAM User '$AWS_USERNAME'."

    # verify it works (need to sleep a bit)
    echo "Waiting 10 seconds for new AccessKey to activate..."
    sleep 10
    AWS_PROFILE_OLD=$AWS_PROFILE
    AWS_PROFILE=$AWS_PROFILE-new
    aws_cli_setup $NEW_ACCESS_KEY_ID $NEW_SECRET_ACCESS_KEY $AWS_PROFILE
    TEST_ACCOUNTID=$(AWS_PROFILE=$AWS_PROFILE aws sts get-caller-identity | jq -r '.Account')
    AWS_PROFILE=$AWS_PROFILE_OLD

    if [ "$ORIG_ACCOUNTID" != "$TEST_ACCOUNTID" ];
    then
        echo "ERROR: New AccessKey didn't fetch same Account ID.  Expected '$ORIG_ACCOUNTID' but got '$TEST_ACCOUNTID'."
        # cleanup, remove new key that isn't working
        iam_user_delete_accesskey $AWS_USERNAME $NEW_ACCESS_KEY_ID
        exit 1
    fi

    # cache old access key for later deletion
    OLD_ACCESS_KEY_ID=$ACCESS_KEY_ID
}

iam_user_delete_accesskey() {
    AWS_USERNAME=$1
    OLD_KEY_ID=$2

    AWS_PROFILE=$AWS_PROFILE aws iam delete-access-key --user-name $AWS_USERNAME --access-key-id $OLD_KEY_ID

    info "Deleted AccessKey '$OLD_KEY_ID' from user '$AWS_USERNAME'."
}

update_aws_secret() {
    SECRET_NAMESPACE=$1
    SECRET_NAME=$2
    # assumes encoded vars are set already by iam_user_create_accesskey

    ssh root@hive-$ENVIRONMENT-master "oc get secret -n $SECRET_NAMESPACE $SECRET_NAME -o json | jq -r \".data.aws_access_key_id = \\\"$ENCODED_ACCESS_KEY_ID\\\" | .data.aws_secret_access_key = \\\"$ENCODED_SECRET_ACCESS_KEY\\\"\" | oc replace -f -"
}

NAMESPACE=$(ssh root@hive-$ENVIRONMENT-master "oc get clusterdeployment --all-namespaces --no-headers | grep \"$CLUSTER_ID \" | awk '{print \$1}'")

ACCESS_KEY_ID=$(ssh root@hive-$ENVIRONMENT-master "oc get secrets -n $NAMESPACE aws -o json | jq -r '.data.aws_access_key_id' | base64 --decode")
SECRET_ACCESS_KEY=$(ssh root@hive-$ENVIRONMENT-master "oc get secrets -n $NAMESPACE aws -o json | jq -r '.data.aws_secret_access_key' | base64 --decode")
AWS_PROFILE=$ENVIRONMENT-$CLUSTER_ID
aws_cli_setup $ACCESS_KEY_ID $SECRET_ACCESS_KEY $AWS_PROFILE
info "Retrived original AccessKey."

######################################
### Create new credentials for osdManagedAdmin

iam_user_create_accesskey "osdManagedAdmin"

# switch to new profile so we can delete the old one
AWS_PROFILE=$ENVIRONMENT-$CLUSTER_ID-new

######################################
### Changes on the hive cluster

# Replace aws-account-operator secret
SECRET_NAME=$(ssh root@hive-$ENVIRONMENT-master "oc -n $NAMESPACE get accountclaim -o jsonpath='{.items[].spec.accountLink}'")-secret
update_aws_secret aws-account-operator $SECRET_NAME 

info "Replaced AWS Account Operator Secret."

# Replace aws secret (in cluster's hive namespace)
update_aws_secret $NAMESPACE aws

info "Replaced Hive AWS Secret."

######################################
### Delete old credentials for osdManagedAdmin

iam_user_delete_accesskey "osdManagedAdmin" "$ACCESS_KEY_ID"

######################################
### Changes on the OSD cluster

# Get kubeconfig
TEMP_DIR=$(mktemp -d)
ssh root@hive-$ENVIRONMENT-master "oc -n $NAMESPACE extract \"\$(oc -n $NAMESPACE get secrets -o name | grep kubeconfig)\" --keys=kubeconfig --to=-" > ${TEMP_DIR}/kubeconfig-${NAMESPACE}

# Update kube-system aws-creds secret (main secret used to mint other credentials)
KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n kube-system get secret aws-creds -o json | jq -r ".data.aws_access_key_id = \"$ENCODED_ACCESS_KEY_ID\" | .data.aws_secret_access_key = \"$ENCODED_SECRET_ACCESS_KEY\"" | KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc replace -f -

info "Replaced OSD kube-system aws-creds Secret."

# restart cloud-credential-operator pod, make sure it has the updated secret
CCO_POD=$(KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n openshift-cloud-credential-operator get pods | grep cloud-credential-operator | awk '{print $1}')
KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n openshift-cloud-credential-operator delete pod $CCO_POD

# Rotate CVO managed credentials (simply delete them)
for CR in $(KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc get credentialsrequests -n openshift-cloud-credential-operator -o json | jq -r '.items[].metadata.name');
do
    KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n openshift-cloud-credential-operator delete credentialsrequest $CR
done

info "Rotated CVO managed CredentialsRequests."

# Rotate other credentials by saving a copy of the CredentialsRequest, deleting the CredentialsRequest, and creating it again
# Note these are in core NS and NOT managed by CVO
# Solution: https://access.redhat.com/solutions/4279111
# Bug (optimization): https://issues.redhat.com/browse/CO-742
rm ${TEMP_DIR}/*.CredentialsRequest.json 2>/dev/null || true

# get original credentialsrequests and delete them
for NS in $(KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc get credentialsrequests --all-namespaces -o json | jq -r '.items[].metadata.namespace' | uniq | grep -e ^openshift -e ^kube -e ^default$ -e ^redhat | grep -v openshift-cloud-credential-operator);
do
    for CR in $(KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc get credentialsrequests -n $NS -o json | jq -r '.items[].metadata.name');
    do
        # filename to stash resource in
        F=${TEMP_DIR}/${CR}_${NS}.CredentialsRequest.json

        # get the original json and clean it up
        KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n $NS get credentialsrequests $CR -o json | jq -r 'del(.status) | del(.metadata.annotations) | del(.metadata.creationTimestamp) | del(.metadata.finalizers) | del(.metadata.generation) | del(.metadata.ownerReferences) | del(.metadata.resourceVersion) | del(.metadata.selfLink) | del(.metadata.uid)' > $F

        # delete the original resource
        KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc -n $NS delete credentialsrequests $CR

        # recreate resource
        KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc create -f $F
        # name of referenced secret
        S=$(cat $F | jq -r '.spec.secretRef.name')

        # cleanup any pods that referenced the secret (note we're ignoring namespace, exceptionally small risk)
        IFS_OLD=$IFS
        IFS=
        for X in $(KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} oc get pods --all-namespaces -o json | jq -r ".items[] | select(.spec.volumes[].secret.secretName == \"$S\") | \"oc -n \" + .metadata.namespace + \" delete pod \" + .metadata.name");
        do
            X="KUBECONFIG=${TEMP_DIR}/kubeconfig-${NAMESPACE} $X"
            # do not wait, just move on
            eval $X &
        done
        IFS=$IFS_OLD

        info "Rotated SRE managed CredentialsRequest '$CR' in '$NS'."
    done
done

# NOTE do not wait for pod deletion.

######################################
### Rotate SRE IAM User Credentials
SECRET_NAME=$(ssh root@hive-$ENVIRONMENT-master "oc -n $NAMESPACE get accountclaim -o jsonpath='{.items[].spec.accountLink}'")-osdmanagedadminsre-secret
ACCESS_KEY_ID=$(ssh root@hive-$ENVIRONMENT-master "oc get secrets -n aws-account-operator $SECRET_NAME -o json | jq -r '.data.aws_access_key_id' | base64 --decode")
SECRET_ACCESS_KEY=$(ssh root@hive-$ENVIRONMENT-master "oc get secrets -n aws-account-operator $SECRET_NAME -o json | jq -r '.data.aws_secret_access_key' | base64 --decode")
AWS_PROFILE=$ENVIRONMENT-$CLUSTER_ID-sre
aws_cli_setup $ACCESS_KEY_ID $SECRET_ACCESS_KEY $AWS_PROFILE
iam_user_create_accesskey "osdManagedAdminSRE"
update_aws_secret aws-account-operator $SECRET_NAME 
iam_user_delete_accesskey "osdManagedAdminSRE" "$OLD_ACCESS_KEY_ID"

info "Rotated SRE IAM User credentials."

######################################
### Wipe AWS Profile data

# can't find a clean cli option to remove them, so will simply set with junk
aws_cli_setup "X" "X" $ENVIRONMENT-$CLUSTER_ID
aws_cli_setup "X" "X" $ENVIRONMENT-$CLUSTER_ID-new
aws_cli_setup "X" "X" $ENVIRONMENT-$CLUSTER_ID-sre
aws_cli_setup "X" "X" $ENVIRONMENT-$CLUSTER_ID-sre-new

info "Done!"
