SHELL := /usr/bin/env bash
include project.mk

ifndef GEN_QUOTA_TEMPLATE
$(error GEN_QUOTA_TEMPLATE is not set; check project.mk file)
endif

CONTAINER_ENGINE=$(shell command -v docker 2>/dev/null || command -v podman 2>/dev/null)
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

.PHONY: default
default: generate-lb-quota-templates

.PHONY: generate-lb-quota-templates
generate-lb-quota-templates:
	if [ -z ${IN_CONTAINER} ]; then \
		$(CONTAINER_ENGINE) pull quay.io/app-sre/python:3 && $(CONTAINER_ENGINE) tag quay.io/app-sre/python:3 python:3 || true; \
		$(CONTAINER_ENGINE) run --user $(CURRENT_UID):$(CURRENT_GID) --rm -v `pwd -P`:`pwd -P`:z python:3 /bin/sh -c "cd `pwd -P`; pip install --upgrade -t . oyaml; ${GEN_QUOTA_TEMPLATE}"; \
	else \
		${GEN_QUOTA_TEMPLATE}; \
	fi

.PHONY: clean
clean:
	rm -rf $(DESTINATION_DIRECTORY)
