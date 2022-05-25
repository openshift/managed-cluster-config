#!/usr/bin/env bash

./generate-managed-list.py --output yaml -s osd-all --path ../../resources/managed/all-osd-resources.yaml
./generate-managed-list.py --output configmap -s osd-namespaces --path ../../deploy/osd-managed-resources/managed-namespaces.ConfigMap.yaml
./generate-managed-list.py --output configmap -s ocp-namespaces --name ocp-namespaces --path ../../deploy/osd-managed-resources/ocp-namespaces.ConfigMap.yaml
