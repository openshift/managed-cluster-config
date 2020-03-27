#!/bin/bash

set -exv

# all custom alerts must have a namespace label
MISSING_NS="false"
for F in $(ls deploy/sre-prometheus)
do
    # requires yq
    MISSING_NS_COUNT=$(cat deploy/sre-prometheus/$F | python -c 'import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))' | jq -r '.spec.groups[].rules[] | select(.namespace == null) and select(.labels.namespace == null)' | wc -l)

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
cat hack/00-osd-managed-cluster-config.selectorsyncset.yaml.tmpl | sort > sorted-before.yaml.tmpl

make

cat hack/00-osd-managed-cluster-config.selectorsyncset.yaml.tmpl | sort > sorted-after.yaml.tmpl

diff sorted-before.yaml.tmpl sorted-after.yaml.tmpl || (echo "Running 'make' caused changes.  Run 'make' and commit changes to the PR to try again." && rm -f sorted-before.yaml.tmpl sorted-after.yaml.tmpl && exit 1)

rm -f sorted-before.yaml.tmpl sorted-after.yaml.tmpl

# script needs to pass for app-sre workflow 
exit 0
