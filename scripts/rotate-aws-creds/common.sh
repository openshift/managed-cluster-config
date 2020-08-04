#!/bin/bash

aws_cli_setup() {
    local KEY_ID=$1
    local SECRET_KEY=$2
    local PROFILE_NAME=$3
    info "Using access key '$KEY_ID'."
    echo -e "${KEY_ID}\n${SECRET_KEY}\nus-east-1\njson\n" | aws configure --profile "$PROFILE_NAME" 2>/dev/null >/dev/null
}

rotate_credential_requests() {
    local TEMP_DIR=$1
    local KUBECONFIG=$2
    local OC=$3
    
    # Rotate other credentials by saving a copy of the CredentialsRequest, deleting the CredentialsRequest, and creating it again
    # Note these are in core NS and NOT managed by CVO
    # Solution: https://access.redhat.com/solutions/4279111
    # Bug (optimization): https://issues.redhat.com/browse/CO-742
    rm "${TEMP_DIR}/*.CredentialsRequest.json" 2>/dev/null || true

    # get original credentialsrequests and delete them
    for NS in $(KUBECONFIG=$KUBECONFIG $OC get credentialsrequests --all-namespaces -o json | jq -r '.items[].metadata.namespace' | uniq | grep -e ^openshift -e ^kube -e ^default$ -e ^redhat | grep -v openshift-cloud-credential-operator);
    do
        for CR in $(KUBECONFIG=$KUBECONFIG $OC get credentialsrequests -n "$NS" -o json | jq -r '.items[].metadata.name');
        do
            # filename to stash resource in
            F=${TEMP_DIR}/${CR}_${NS}.CredentialsRequest.json

            # get the original json and clean it up
            KUBECONFIG=$KUBECONFIG $OC -n "$NS" get credentialsrequests "$CR" -o json | jq -r 'del(.status) | del(.metadata.annotations) | del(.metadata.creationTimestamp) | del(.metadata.finalizers) | del(.metadata.generation) | del(.metadata.ownerReferences) | del(.metadata.resourceVersion) | del(.metadata.selfLink) | del(.metadata.uid)' > "$F"

            # delete the original resource
            KUBECONFIG=$KUBECONFIG $OC -n "$NS" delete credentialsrequests "$CR"

            # recreate resource
            KUBECONFIG=$KUBECONFIG $OC create -f "$F"
            # name of referenced secret
            S=$(jq -r '.spec.secretRef.name' "$F")

            # cleanup any pods that referenced the secret (note we're ignoring namespace, exceptionally small risk)
            IFS_OLD=$IFS
            IFS=
            for X in $(KUBECONFIG=$KUBECONFIG $OC get pods --all-namespaces -o json | jq -r ".items[] | select(.spec.volumes[].secret.secretName == \"$S\") | \"$OC -n \" + .metadata.namespace + \" delete pod \" + .metadata.name");
            do
                X="KUBECONFIG=$KUBECONFIG $X"
                # do not wait, just move on
                eval "$X" &
            done
            IFS=$IFS_OLD

            info "Rotated SRE managed CredentialsRequest '$CR' in '$NS'."
        done
    done
}

iam_user_create_accesskey() {
    local AWS_USERNAME=$1

    info "IAM User: $AWS_USERNAME"

    local ORIG_ACCOUNTID
    ORIG_ACCOUNTID=$(AWS_PROFILE=$AWS_PROFILE aws sts get-caller-identity | jq -r '.Account')

    info "Account ID: $ORIG_ACCOUNTID"

    # create a new access key
    local ACCESS_KEY_JSON
    ACCESS_KEY_JSON=$(AWS_PROFILE=$AWS_PROFILE aws iam create-access-key --user-name "$AWS_USERNAME")

    # get encoded access key data
    NEW_ACCESS_KEY_ID=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.AccessKeyId' | tr -d '\n')
    ENCODED_ACCESS_KEY_ID=$(echo -n "$NEW_ACCESS_KEY_ID" | base64)
    NEW_SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey' | tr -d '\n')
    ENCODED_SECRET_ACCESS_KEY=$(echo -n "$NEW_SECRET_ACCESS_KEY" | base64)

    info "Created new AccessKey for IAM User '$AWS_USERNAME'."

    # verify it works (need to sleep a bit)
    echo "Waiting 10 seconds for new AccessKey to activate..."
    sleep 10
    AWS_PROFILE_OLD=$AWS_PROFILE
    AWS_PROFILE=$AWS_PROFILE-new
    aws_cli_setup "$NEW_ACCESS_KEY_ID" "$NEW_SECRET_ACCESS_KEY" "$AWS_PROFILE"
    local TEST_ACCOUNTID
    TEST_ACCOUNTID=$(AWS_PROFILE=$AWS_PROFILE aws sts get-caller-identity | jq -r '.Account')
    AWS_PROFILE=$AWS_PROFILE_OLD

    if [ "$ORIG_ACCOUNTID" != "$TEST_ACCOUNTID" ];
    then
        echo "ERROR: New AccessKey didn't fetch same Account ID.  Expected '$ORIG_ACCOUNTID' but got '$TEST_ACCOUNTID'."
        # cleanup, remove new key that isn't working
        iam_user_delete_accesskey "$AWS_USERNAME" "$NEW_ACCESS_KEY_ID"
        exit 1
    fi

    # cache old access key for later deletion
    OLD_ACCESS_KEY_ID=$ACCESS_KEY_ID
}

aws_iam_username() {
    DEFAULT_USER=$1
    unset KEY_USERNAME
    # AWS states in the cli documentation that list-user returns tags but it does not
    # https://github.com/boto/boto3/issues/1855
    USERNAME_PREFIX="${DEFAULT_USER}-"
    if [[ "${CCS_CLUSTER}" == "1" ]]; then
        USERNAME_PREFIX="${DEFAULT_USER}-"
        for USERNAME in $(AWS_PROFILE=$AWS_PROFILE aws iam list-users | jq -r " .Users[].UserName | select(startswith(\"${USERNAME_PREFIX}\"))"); do
            CLAIM_LINK=$(AWS_PROFILE=${AWS_PROFILE} aws iam list-user-tags --user-name ${USERNAME} | jq -r ".Tags[] | select ( .Key == \"clusterClaimLink\" ) | .Value ")
            if [[ "${CLAIM_LINK}" == "${CLUSTER_NAME}" ]]; then
                KEY_USERNAME=${USERNAME}
            fi
        done
    else
        KEY_USERNAME=${DEFAULT_USER}
    fi

    if [ -z "${KEY_USERNAME}" ]; then
        info "Could not find AWS user for ${DEFAULT_USER}"
        exit 1
    fi
}

iam_user_delete_accesskey() {
    AWS_USERNAME=$1
    OLD_KEY_ID=$2

    AWS_PROFILE=$AWS_PROFILE aws iam delete-access-key --user-name $AWS_USERNAME --access-key-id $OLD_KEY_ID

    info "Deleted AccessKey '$OLD_KEY_ID' from user '$AWS_USERNAME'."
}
