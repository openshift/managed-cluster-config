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
ifndef SELECTOR_SYNC_SET_DESTINATION
$(error SELECTOR_SYNC_SET_DESTINATION is not set; check project.mk file)
endif
ifndef REPO_NAME
$(error REPO_NAME is not set; check project.mk file)
endif

.PHONY: nmalik
nmalik:
	echo "${REPO_NAME}"

.PHONY: default
default: clean resource-quotas generate-syncset

.PHONY: generate-oauth-templates
generate-oauth-templates:
	# The html goes into a secret.  if it's too big, it can't be updated so break it into one secret per html.
	# Each SSS must not be too big as well.  each sub-dir of deploy/ becomes a SSS.  therefore each of the html
	# becomes a separate dir.  This is a k8s limitation for annotation value size.
	for TYPE in login providers errors; do \
		oc --config=.kubeconfig create secret generic osd-oauth-templates-$$TYPE -n openshift-config --from-file=$$TYPE.html=source/html/$$TYPE.html --dry-run -o yaml > deploy/osd-oauth-templates-$$TYPE/osd-oauth-templates-$$TYPE.secret.yaml; \
	done

.PHONY: generate-syncset
generate-syncset: generate-oauth-templates
	docker run --rm -v `pwd`:`pwd` python:2.7.15 /bin/sh -c "cd `pwd`; pip install pyyaml; scripts/generate_syncset.py -t ${SELECTOR_SYNC_SET_TEMPLATE_DIR} -y ${YAML_DIRECTORY} -d ${SELECTOR_SYNC_SET_DESTINATION} -r ${REPO_NAME}"

.PHONY: clean 
clean: 
	rm -rf ${SELECTOR_SYNC_SET_DESTINATION}
	@$(MAKE) --directory=deploy/resource-quotas clean

.PHONY: resource-quotas
resource-quotas:
	@$(MAKE) --directory=deploy/resource-quotas clean all

.PHONY: git-commit
git-commit:
	git add ${SELECTOR_SYNC_SET_DESTINATION}
	git commit -m "Updated selectorsynceset template added"
