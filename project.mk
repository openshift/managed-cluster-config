#Project specific values
YAML_DIRECTORY?=deploy
GENERATED_YAML_DIRECTORY?=generated_deploy
SELECTOR_SYNC_SET_TEMPLATE_DIR?=scripts/templates/
GIT_ROOT?=$(shell git rev-parse --show-toplevel 2>&1)

# WARNING: REPO_NAME will default to the current directory if there are no remotes
REPO_NAME=managed-cluster-config

ifdef UID_OWNER
CHANGE_UID=chown -R ${UID_OWNER} ${GIT_ROOT}/${GENERATED_YAML_DIRECTORY} ; find . -name \"50-GENERATED*\" -exec chown ${UID_OWNER} {} +
endif
ifdef GID_OWNER
CHANGE_GID=chown -R :${GID_OWNER} ${GIT_ROOT}/${GENERATED_YAML_DIRECTORY} ; find . -name \"50-GENERATED*\" -exec chown :${GID_OWNER} {} +
endif

#Script variables
GEN_TEMPLATE?=scripts/generate_template.py -t ${SELECTOR_SYNC_SET_TEMPLATE_DIR} -y ${GENERATED_YAML_DIRECTORY} -d ${GIT_ROOT}/hack/ -r ${REPO_NAME}
GEN_POLICY_CONFIG?=scripts/generate-resources.py -y ${YAML_DIRECTORY} 
ENFORCE_BACKPLANE_RULES?=scripts/enforce-backplane-rules.py
GEN_CMO_CONFIG?=scripts/generate-cmo-config.py
