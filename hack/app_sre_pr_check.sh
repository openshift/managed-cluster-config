#!/bin/bash

set -exv

# if running `make` changes anything, fail the build

make

test 0 -eq $(git status --porcelain | wc -l) || (echo "Running 'make' caused changes.  Run 'make' and commit changes to the PR to try again." && exit 1)

# script needs to pass for app-sre workflow 
exit 0
