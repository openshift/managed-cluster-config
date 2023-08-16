#!/bin/bash

DIRECTORY="/tmp/*/"
FILENAME="policy-generator-config.yaml"
ROOT_DIR=$PWD
for dir in $DIRECTORY; do
    cd $dir
    name=$(grep "\- name:" $FILENAME | cut -d: -f2- | xargs)
    PolicyGenerator $FILENAME > $ROOT_DIR/generated_deploy/acm-policies/50-GENERATED-$name.Policy.yaml
    cd $ROOT_DIR
done
