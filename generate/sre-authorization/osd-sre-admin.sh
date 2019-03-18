#!/bin/bash

BLACKLIST=`cat blacklist.json`

echo "apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: osd-sre-admin
rules:"

# /api
GROUP=""
for VERSION in `oc get --raw /api | jq -r .versions[] | sort`;
do
    # if the group isn't blacklisted just allow everything
    COUNT=`echo $BLACKLIST | jq ".[] | select(.apiGroup == \"$GROUP\")" | wc -l`

    if [ "$COUNT" == "0" ];
    then
        # not blacklisted, continue
        echo "- apiGroups:"
        echo "  - \"\""
        echo "  resources:"
        echo "  - '*'"
        echo "  verbs:"
        echo "  - '*'"
        continue
    fi

    for RESOURCE in `oc get --raw /api/${VERSION} | jq -r .resources[].name | sort`;
    do
        # something was blacklisted, see if it was the resource
        COUNT=`echo $BLACKLIST | jq ".[] | select(.apiGroup == \"$GROUP\") | select(.resources[] == \"$RESOURCE\")" | wc -l`

        if [ "$COUNT" == "0" ];
        then
            # not blacklisted, continue
            echo "- apiGroups:"
            echo "  - \"\""
            echo "  resources:"
            echo "  - $RESOURCE"
            echo "  verbs:"
            echo "  - '*'"
            continue
        fi

        echo "- apiGroups:"
        echo "  - \"\""
        echo "  resources:"
        echo "  - $RESOURCE"
        echo "  verbs:"

        for VERB in `oc get --raw /api/${VERSION} | jq -r ".resources[] | select(.name == \"$RESOURCE\") | .verbs[]" | sort`;
        do
            # a verb was blacklisted, check it...
            COUNT=`echo $BLACKLIST | jq ".[] | select(.apiGroup == \"$GROUP\") | select(.resources[] == \"$RESOURCE\") | select(.verbs[] == \"$VERB\")" | wc -l`

            if [ "$COUNT" == "0" ];
            then
                echo "  - $VERB"
            else
                echo "  # BLACKLIST: $VERB"
            fi
        done
    done
done

# /apis
for GROUP in `oc get --raw /apis | jq -r .groups[].name | sort`;
do
    # if the group isn't blacklisted just allow everything
    COUNT=`echo $BLACKLIST | jq ".[] | select(.apiGroup == \"$GROUP\")" | wc -l`

    if [ "$COUNT" == "0" ];
    then
        # not blacklisted, continue
        echo "- apiGroups:"
        echo "  - $GROUP"
        echo "  resources:"
        echo "  - '*'"
        echo "  verbs:"
        echo "  - '*'"
        continue
    fi

    for VERSION in `oc get --raw /apis/${GROUP} | jq -r .versions[].version | sort`;
    do
        for RESOURCE in `oc get --raw /apis/${GROUP}/${VERSION} | jq -r .resources[].name | sort`;
        do
            # something was blacklisted, see if it was the resource
            COUNT=`echo $BLACKLIST | jq ".[] | select(.apiGroup == \"$GROUP\") | select(.resources[] == \"$RESOURCE\")" | wc -l`

            if [ "$COUNT" == "0" ];
            then
                # not blacklisted, continue
                echo "- apiGroups:"
                echo "  - $GROUP"
                echo "  resources:"
                echo "  - $RESOURCE"
                echo "  verbs:"
                echo "  - '*'"
                continue
            fi

            echo "- apiGroups:"
            echo "  - $GROUP"
            echo "  resources:"
            echo "  - $RESOURCE"
            echo "  verbs:"

            for VERB in `oc get --raw /apis/${GROUP}/${VERSION} | jq -r ".resources[] | select(.name == \"$RESOURCE\") | .verbs[]" | sort`;
            do
                # a verb was blacklisted, check it...
                COUNT=`echo $BLACKLIST | jq ".[] | select(.apiGroup == \"$GROUP\") | select(.resources[] == \"$RESOURCE\") | select(.verbs[] == \"$VERB\")" | wc -l`

                if [ "$COUNT" == "0" ];
                then
                    echo "  - $VERB"
                else
                    echo "  # BLACKLIST: $VERB"
                fi
            done
        done
    done
done

echo "- nonResourceURLs:
  - '*'
  verbs:
  - '*'"
