# templates
TEMPLATE_DIR?=templates
DESTINATION_DIRECTORY?=quota

AWS_SC?=gp2 gp2-csi
GCP_SC?=standard standard-csi
SC_QUOTAS?=100 600 1100 1600 2100 2600 3100 3600 4100 7100

# final script command
GEN_QUOTA_TEMPLATE?=./generate.py -t ${TEMPLATE_DIR} -d ${DESTINATION_DIRECTORY} -a ${AWS_SC} -g ${GCP_SC} --quotas ${SC_QUOTAS}
