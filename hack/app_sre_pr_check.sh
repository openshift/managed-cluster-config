#!/bin/bash

set -exv

trap "rm -f sorted-before*.yaml.tmpl sorted-after*.yaml.tmpl" EXIT

# all custom alerts must have a namespace label
MISSING_NS="false"
for F in $(find ./deploy/sre-prometheus -type f -iname '*prometheusrule.yaml')
do
    # requires yq
    MISSING_NS_COUNT=$(cat $F | python -c 'import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))' | jq -r '.spec.groups[].rules[] | select(.alert != null) | select(.namespace == null) and select(.labels.namespace == null)' | wc -l)

    if [ "$MISSING_NS_COUNT" != "0" ]
    then
        echo "ERROR: Rule missing 'namespace' in file '$F'"
        MISSING_NS="true"
    fi
done

if [ "$MISSING_NS" == "true" ]
then
    echo "ERROR: one or more files missing 'namespace' label, see 'ERROR' output in above logs"
    exit 2
fi

# if running `make` changes anything, fail the build
# order is inconsistent across systems, sort the template file.. it's not perfect but it's better than nothing
for environment in integration stage production;
do
    cat hack/00-osd-managed-cluster-config-${environment}.yaml.tmpl | sort > sorted-before-${environment}.yaml.tmpl
done

# remove all generated acm policies files in order to determine if they have changed
rm -f deploy/acm-policies/50-GENERATED-*.yaml

make

for environment in integration stage production;
do
    cat hack/00-osd-managed-cluster-config-${environment}.yaml.tmpl | sort > sorted-after-${environment}.yaml.tmpl
    diff sorted-before-${environment}.yaml.tmpl sorted-after-${environment}.yaml.tmpl || (echo "Running 'make' caused changes.  Run 'make' and commit changes to the PR to try again." && exit 1)
done

# check if roleref has been modified in a clusterrolebinding/rolebinding as a part of this change
for fl in $( git diff --name-only --diff-filter=M  origin/master deploy ':!deploy/acm-policies/50-GENERATED-*' )
do
  if cat ${fl} | grep -i "RoleBinding" | grep -q "kind:" ; then
    # NOTE Remove 'namespace' from roleRef as this is not part of the specification and has not impact on the resource.
    #      Excluding 'namespace' from the PR check allows us to remove it and therefore get ACM Policy validation to work correctly.
    ROLEREF_MASTER=$(git show origin/master:${fl} | python -c 'import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))' | jq -r 'del(.roleRef.namespace) | .roleRef' )
    ROLEREF_PR=$(cat ${fl} | python -c 'import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))' | jq -r '.roleRef' )
    # see if roleref has changed compared to master
    if ! jq -ne --argjson a "$ROLEREF_MASTER" --argjson b "$ROLEREF_PR" '$a == $b'; then
      echo "ERROR: roleref modification is not supported. Please create a new ClusterRoleBinding/RoleBinding instead. See https://github.com/openshift/ops-sop/blob/master/v4/knowledge_base/mcc-modify-roleref.md"
      exit 1
    fi
  fi
done

# there should be no local changes after running all these checks
# ignore the "hack" dir as template updates are handled above
UNCOMMITTED_CHANGES=$(git status --porcelain  | grep -v -e ".*sorted.*tmpl" -e "...hack.*" | wc -l)
if [ "$UNCOMMITTED_CHANGES" != "0" ];
then
  echo "ERROR: uncommitted changes indicate generating content resulted in some file changes:"
  git status --porcelain  | grep -v -e ".*sorted.*tmpl" -e "...hack.*"
  echo "ERROR: run 'make' and commit changes before attempting PR check again"
  exit 1
fi

# script needs to pass for app-sre workflow
exit 0
