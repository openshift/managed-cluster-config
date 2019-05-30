SHELL = /usr/bin/env bash -e
include functions.mk
include values.mk

default: all

all: namespace_labels quotas
quotas: 15-selectorsyncset.clusterresourcequota.yaml
namespace_labels: pv_namespace_labels lb_namespace_labels

pv_namespace_labels:
	@for ns in $(PERSISTENT_VOLUME_EXCEPTIONS); do \
		fragment="$$(echo $$ns | awk -f ../../scripts/jsonify.awk pv="$(PERSISTENT_VOLUME_EXCEPTIONS)" lb="$(LOAD_BALANCER_EXCEPTIONS)" label_lb=$(LB_EXCLUSION_LABEL_NAME) label_pv=$(PV_EXCLUSION_LABEL_NAME))" ;\
		$(call process_template,templates/10-selectorsyncset.namespace.yaml.tmpl,10-selectorsyncset.namespace.$${ns}.yaml,$$fragment,$$ns) ;\
	done

lb_namespace_labels:
	@for ns in $(LOAD_BALANCER_EXCEPTIONS); do \
		fragment="$$(echo $$ns | awk -f ../../scripts/jsonify.awk pv="$(PERSISTENT_VOLUME_EXCEPTIONS)" lb="$(LOAD_BALANCER_EXCEPTIONS)" label_lb=$(LB_EXCLUSION_LABEL_NAME) label_pv=$(PV_EXCLUSION_LABEL_NAME))" ;\
		$(call process_template,templates/10-selectorsyncset.namespace.yaml.tmpl,10-selectorsyncset.namespace.$${ns}.yaml,$$fragment,$$ns) ;\
	done

15-selectorsyncset.clusterresourcequota.yaml: templates/15-selectorsyncset.clusterresourcequota.yaml.tmpl
	@$(call process_template,templates/$@.tmpl,$@)

.PHONY: clean
clean:
	@rm -f 10-*.yaml 15-*.yaml
