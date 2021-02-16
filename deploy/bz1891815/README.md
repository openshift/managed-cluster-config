References:
* [BZ 1891815](https://bugzilla.redhat.com/show_bug.cgi?id=1891815)
* [Temporary fix for BZ 1891815](https://issues.redhat.com/browse/OSD-5813)

Cause likely GC.  Introduced in 4.5.  Higher frequency in 4.5.16 due to client-go bump.  Short term fix is periodic restart of prometheus-operator pod.