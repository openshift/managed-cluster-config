Requirements:
* [OSD-6053](https://issues.redhat.com/browse/OSD-6053) - Freeze logging while in change freeze
  * See [freeze/](freeze/) and it's [README](freeze/README.md)
* [OSD-6322](https://issues.redhat.com/browse/OSD-6322) - No in-cluster logging support for ROSA.
* [OSD-6324](https://issues.redhat.com/browse/OSD-6324) - No in-cluster logging support for OSD 4.7+
  * See [with-alerts/](with-alerts/) and [without-alerts/](without-alerts/)

osd-logging/
- resources that do not get deleted when moving to unsupported

osd-logging/supported/
- resources that get deleted when moving to unsupported

