#!/usr/bin/env bash

./generate-managed-list.py --output yaml --all --path ../../resources/managed/all-osd-resources.yaml
./generate-managed-list.py --output configmap --path ../../deploy/osd-managed-resources/managed-namespaces.ConfigMap.yaml
