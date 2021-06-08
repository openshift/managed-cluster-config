SHELL := /usr/bin/env bash
# Include project specific values file
# Requires the following variables:
# - YAML_DIRECTORY
# - SELECTOR_SYNC_SET_TEMPLATE_DIR
# - SELECTOR_SYNC_SET_DESTINATION
# - REPO_NAME
include project.mk

#Validate variables in project.mk exist
ifndef YAML_DIRECTORY
$(error YAML_DIRECTORY is not set; check project.mk file)
endif
ifndef SELECTOR_SYNC_SET_TEMPLATE_DIR
$(error SELECTOR_SYNC_SET_TEMPLATE_DIR is not set; check project.mk file)
endif
ifndef REPO_NAME
$(error REPO_NAME is not set; check project.mk file)
endif
ifndef GEN_TEMPLATE
$(error GEN_TEMPLATE is not set; check project.mk file)
endif

CONTAINER_ENGINE=$(shell command -v docker 2>/dev/null || command -v podman 2>/dev/null)

ifeq ($(CONTAINER_ENGINE),)
# Running already in a container
OC := oc --dry-run=true --kubeconfig=.kubeconfig
else
# Run the oc inside container
OC := $(CONTAINER_ENGINE) run --rm -v `pwd -P`:`pwd -P`:z -w=`pwd` quay.io/openshift/origin-cli:4.7.0 oc --dry-run=client --kubeconfig=.kubeconfig
endif

.PHONY: default
default: generate-oauth-templates generate-rosa-brand-logo generate-hive-templates

.PHONY: generate-oauth-templates
generate-oauth-templates:
	# The html goes into a secret.  if it's too big, it can't be updated so break it into one secret per html.
	# Each SSS must not be too big as well.  each sub-dir of deploy/ becomes a SSS.  therefore each of the html
	# becomes a separate dir.  This is a k8s limitation for annotation value size.
	for TYPE in login providers errors; do \
		$(OC) create secret generic osd-oauth-templates-$$TYPE -n openshift-config --from-file=$$TYPE.html=source/html/osd/$$TYPE.html -o yaml > deploy/osd-oauth-templates-$$TYPE/osd-oauth-templates-$$TYPE.secret.yaml; \
		$(OC) create secret generic rosa-oauth-templates-$$TYPE -n openshift-config --from-file=$$TYPE.html=source/html/rosa/$$TYPE.html -o yaml > deploy/rosa-oauth-templates-$$TYPE/rosa-oauth-templates-$$TYPE.secret.yaml; \
	done

.PHONY: generate-rosa-brand-logo
generate-rosa-brand-logo:
	$(OC) create configmap rosa-brand-logo -n openshift-config --from-file source/html/rosa/rosa-brand-logo.svg -o yaml > deploy/rosa-console-branding-configmap/rosa-brand-logo.yaml

.PHONY: generate-hive-templates
generate-hive-templates: generate-oauth-templates
	if [ -z ${IN_CONTAINER} ]; then \
		$(CONTAINER_ENGINE) pull quay.io/app-sre/python:3 && $(CONTAINER_ENGINE) tag quay.io/app-sre/python:3 python:3 || true; \
		$(CONTAINER_ENGINE) run --rm -v `pwd -P`:`pwd -P`:z python:3 /bin/sh -c "cd `pwd -P`; pip install oyaml; ${GEN_TEMPLATE}"; \
	else \
		${GEN_TEMPLATE}; \
	fi
