# Overview

We needed in [OSD-4230](https://issues.redhat.com/browse/OSD-4230) to patch the `openshift-operator-lifecycle-manager` namespace to add a label that could be used in NetworkPolicy.  We don't do anything else directly with that namespace and may need a way to do similar tweaks in the future.  So this will become a single SSS to patch namespace labels for these use cases.

# Guideline

The general guideline for these labels are:
- label key is `name`
- label value is the Namespaces .metadata.name

# Why isn't this done for all Namespaces?  

It could be, there's no harm in it.  But we'd need to write software to do the patching as we cannot assume a static set of Namespaces.  Given we don't have a requirement for this yet we will not take on this engineering work as it will require work to develop, deploy, and maintain.  This simple patch will cover our known use cases until such time in the future that we have a concrete requirement for a more comprehensive solution.
