#!/bin/bash

set -exv

# if running `make` changes anything, fail the build
# order is inconsistent across systems, sort the template file.. it's not perfect but it's better than nothing
cat hack/00-osd-managed-cluster-config.selectorsyncset.yaml.tmpl | sort > sorted-before.yaml.tmpl

make

cat hack/00-osd-managed-cluster-config.selectorsyncset.yaml.tmpl | sort > sorted-after.yaml.tmpl

diff sorted-before.yaml.tmpl sorted-after.yaml.tmpl || (echo "Running 'make' caused changes.  Run 'make' and commit changes to the PR to try again." && rm -f sorted-before.yaml.tmpl sorted-after.yaml.tmpl && exit 1)

rm -f sorted-before.yaml.tmpl sorted-after.yaml.tmpl

# script needs to pass for app-sre workflow 
exit 0
