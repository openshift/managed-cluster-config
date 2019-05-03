SHELL := /usr/bin/env bash
# Include project specific values file
# Requires the following variables:
# - YAML_DIRECTORY
# - SELECTOR_SYNC_SET_TEMPLATE
# - SELECTOR_SYNC_SET_DESTINATION
# - GIT_URL
# - GIT_HASH
include project.mk

#Validate variables in project.mk exist
ifndef YAML_DIRECTORY
$(error YAML_DIRECTORY is not set; check project.mk file)
endif
ifndef SELECTOR_SYNC_SET_TEMPLATE
$(error SELECTOR_SYNC_SET_TEMPLATE is not set; check project.mk file)
endif
ifndef SELECTOR_SYNC_SET_DESTINATION
$(error SELECTOR_SYNC_SET_DESTINATION is not set; check project.mk file)
endif
ifndef GIT_URL
$(error SELECTOR_SYNC_SET_DESTINATION is not set; check project.mk file)
endif
ifndef GIT_HASH
$(error SELECTOR_SYNC_SET_DESTINATION is not set; check project.mk file)
endif

.PHONY: default
default: clean generate-syncset

.PHONY: generate-syncset
generate-syncset: 
	scripts/generate_syncset.py -t ${SELECTOR_SYNC_SET_TEMPLATE} -y ${YAML_DIRECTORY} -d ${SELECTOR_SYNC_SET_DESTINATION} -u ${GIT_URL} -c ${GIT_HASH}

.PHONY: clean 
clean: 
	rm -rf ${SELECTOR_SYNC_SET_DESTINATION}