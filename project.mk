#Project specific values
YAML_DIRECTORY?=deploy
SELECTOR_SYNC_SET_TEMPLATE_DIR?=scripts/templates/
GIT_ROOT?=$(shell git rev-parse --show-toplevel 2>&1)
SELECTOR_SYNC_SET_DESTINATION?=${GIT_ROOT}/hack/00-osd-managed-cluster-config.selectorsyncset.yaml.tmpl

# WARNING: REPO_NAME will default to the current directory if there are no remotes
REPO_NAME?=$(shell basename $$((git config --get-regex remote\.*\.url 2>/dev/null || pwd) | head -n1 | sed 's|.git||g'))
