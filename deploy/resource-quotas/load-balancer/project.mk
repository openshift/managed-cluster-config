# script parameters
TEMPLATE_DIR?=templates
DESTINATION_DIRECTORY?=quota
LB_QUOTA_COUNTS?=0 4 8 12 16 20

# final script command
GEN_QUOTA_TEMPLATE?=./generate.py -t ${TEMPLATE_DIR} --destination ${DESTINATION_DIRECTORY} --quotas ${LB_QUOTA_COUNTS}
