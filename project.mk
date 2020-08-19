#Project specific values
YAML_DIRECTORY?=deploy
SELECTOR_SYNC_SET_TEMPLATE_DIR?=scripts/templates/
GIT_ROOT?=$(shell git rev-parse --show-toplevel 2>&1)

# WARNING: REPO_NAME will default to the current directory if there are no remotes
REPO_NAME=managed-cluster-config

#Script variables
GEN_TEMPLATE?=scripts/generate_template.py -t ${SELECTOR_SYNC_SET_TEMPLATE_DIR} -y ${YAML_DIRECTORY} -d ${GIT_ROOT}/hack/ -r ${REPO_NAME}
