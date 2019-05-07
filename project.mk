#Project specific values
YAML_DIRECTORY?=deploy
SELECTOR_SYNC_SET_TEMPLATE?=scripts/templates/selectorsyncset.yaml
SELECTOR_SYNC_SET_DESTINATION?=00-osd-manged-cluster-config.selectorsyncset.yaml
GIT_HASH?=$(shell git rev-parse --short=7 HEAD 2>&1)