Requirements:
* [OSD-6053](https://issues.redhat.com/browse/OSD-6053) - Freeze logging while in change freeze
  * See [freeze/](freeze/) and it's [README](freeze/README.md)
* [OSD-6322](https://issues.redhat.com/browse/OSD-6322) - No in-cluster logging support for ROSA.
* [OSD-6324](https://issues.redhat.com/browse/OSD-6324) - No in-cluster logging support for OSD 4.7+
  * See [with-alerts/](with-alerts/) and [without-alerts/](without-alerts/)

osd-logging/
- resources that do not get deleted when moving to unsupported

osd-logging/freeze/
- resources for freeze window management, applies only for supported logging

osd-logging/supported/
- resources that get deleted when moving to unsupported

osd-logging/unsupported/
- resources for unsupported logging, they do not get deleted if sss no longer applies

Short term, the OperatorGroup will be created in `osd-logging/unsupported/` because of https://issues.redhat.com/browse/OSD-6324.  It will be resolved as a part of https://issues.redhat.com/browse/LOG-1091