# This takes several inputs and produces `kubectl patch` fragments.
# Inputs:
# stdin - The namespace to work with
# pv - list of namespaces which are exempt from PV quotas
# lb - list of namespaces which are exempt from LB quotas
# label_pv - what to label those PV-exempt namespaces (value is False)
# label_pv - what to label those LB-exempt namespaces (value is False) 
# Output is inentionally escaping double quotes for use in Makefile:
# VAR := $(shell echo namespace | awk -f jsonify.awk pv=namespace lb=namespace label_pv=label_pv label_lb=label_lb)
# VAR now is literally: {\"label_pv\":\"False\",\"label_lb\":\"False\"}
# This can be used throughout the Makefile without fear that make will strip
# the quotes, now a target such as:
# vardump:
#   @echo $(VAR)
# result is {"label_pv":"False","label_lb":"False"}
BEGIN {FS=" "}
{
  namespace=$1
  split(pv,pvexempt)
  split(lb,lbexempt)
}
END {
  if (length(pv) == 0) {
    print "Must specify pv namespace exemptions as pv=\"list of namespaces\""
    exit 1
  }
  if (length(lb) == 0) {
    print "Must specify lb namespace exemptions as lb=\"list of namespaces\""
    exit 1
  }
  if (length(label_pv) == 0) {
    print "Must specify label to apply for PV exemptions label_pv=\"label\""
    exit 1
  }
  if (length(label_lb) == 0) {
    print "Must specify label to apply for LB exemptions label_lb=\"label\""
    exit 1
  }

  for (p in pvexempt)
    if (pvexempt[p] == namespace) {
      if (out[namespacex])
        out[namespace] = (out[namespace] ",")
      out[namespace] = (out[namespace] "\\\"" label_pv "\\\":\\\"False\\\"")
    }
  for (l in lbexempt)
    if (lbexempt[l] == namespace) {
      if (out[namespace])
        out[namespace] = (out[namespace] ",")
      out[namespace] = (out[namespace] "\\\"" label_lb "\\\":\\\"False\\\"")
    }
  if (length(out[namespace]) > 0)
    print out[namespace]

}
