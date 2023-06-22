SHELL = /usr/bin/env bash -e
include functions.mk
include values.mk

default: all

all: namespace_labels quotas
quotas: 15-resource.clusterresourcequota.yaml

.PHONY: namespace_labels
namespace_labels:
	@for ns in $(shell echo $(LOAD_BALANCER_EXCEPTIONS) $(PERSISTENT_VOLUME_EXCEPTIONS) | tr ' ' '\n' | sort -u); do \
		fragment="$$(echo $$ns | awk -f ../../scripts/jsonify.awk pv="$(PERSISTENT_VOLUME_EXCEPTIONS)" lb="$(LOAD_BALANCER_EXCEPTIONS)" label_lb=$(LB_EXCLUSION_LABEL_NAME) label_pv=$(PV_EXCLUSION_LABEL_NAME))" ;\
		$(call process_template,templates/10-patch.selectorsyncset.namespace.yaml.tmpl,10-patch.namespace.$${ns}.yaml,$$fragment,$$ns) ;\
	done

15-resource.clusterresourcequota.yaml: templates/15-resource.clusterresourcequota.yaml.tmpl
	@$(call process_template,templates/$@.tmpl,$@)

.PHONY: clean
clean:
	@rm -f 10-*.yaml 15-*.yaml
