# bz1980755 HighSubscriptionSyncRateSRE PrometheusRule

This location manages a `PrometheusRule` alert intended to highlight clusters where an operator may be impacted by [BZ1980755](https://bugzilla.redhat.com/show_bug.cgi?id=1980755).

The bug can be observed if the `subscription_sync_total` metric for a subscription rises at a steady rate. Under normal conditions this count should increment very slowly.

The current values have been chosen through observation of impacted clusters in the fleet.

## Contact

Matt Bargenquast mbargenq@redhat.com
