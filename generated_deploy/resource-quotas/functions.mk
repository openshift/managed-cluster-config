# $1 - template file
# $2 - destination (rendered) file
# $3 - label JSON fragment
# $4 - exempt namespace
define process_template
	sed -e "s|\#EXEMPT_NAMESPACE\#|$(4)|g" \
		-e "s|\#LABELS\#|$(3)|g" \
		-e "s|\#PV_EXCLUSION_LABEL_NAME\#|${PV_EXCLUSION_LABEL_NAME}|g" \
		-e "s|\#LB_EXCLUSION_LABEL_NAME\#|${LB_EXCLUSION_LABEL_NAME}|g" \
		-e "s|\#DEFAULT_PV_QUOTA\#|${DEFAULT_PV_QUOTA}|g" \
		-e "s|\#DEFAULT_LB_QUOTA\#|${DEFAULT_LB_QUOTA}|g" \
		$(1) > $(2)
endef
