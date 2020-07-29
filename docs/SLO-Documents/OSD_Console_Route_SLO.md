# **OSD Console Ingress Route - SLO Document**
_adapted from [The Google SRE book](https://landing.google.com/sre/workbook/chapters/slo-document/)_


This document describes the SLOs for the ReplaceMeService.

| **Status**    | **Work In Progress**                        |
| ------------- | ------------------------------------------- |
| Author        | Shay Ulmer                                  |
| Date          | 29/07/2020                                  |
| Reviewers     | Manuel Dewald, Rick Rackow, Pat Cremin      |
| Approvers     | \<Service Owner\>                           |
| Approval Date | \<Approval Date\>                           |
| Revisit Date  | \<Empty on initial commit\>                 |

##### **Service Overview**

The console route exists within the Openshift Ingress Router, and is enabling the access of end users and OSD SRE team to the web UI in order to manage OSD workload.
The SLO uses a four-week rolling window.

##### **SLIs and SLOs**

| Category     | SLI                                                                                                                                                                     | SLO                                                      | Prometheus Query |
|--------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------|------------------|
| Availability | The proportion of successful requests, as measured from the <SERVICE\|ROUTER\|ELB> metrics.                                                                             | 99.5% Success (3.36 Hours of error budget)                                              |                  |

Latency SLI and SLO will be addressed, defined and implemented in future revisit of this document.

##### **Rationale**

Availability SLI was based on measurement over the period
20/07/2020 to 29/07/2020 on a staging cluster.
This document will be revisited and adjusted when a production cluster
will be available for measurement.
All other numbers were picked by the
author and the services were verified to be running at or above those
levels.

No attempt has yet been made to verify that these numbers correlate
strongly with user experience.

##### **Error Budget**

Each objective has a separate error budget, defined as 100% minus (–)
the goal for that objective. For example, if there have been 1,000,000
requests to the API server in the previous four weeks, the API
availability error budget is 3% (100% – 97%) of 1,000,000: 30,000
errors.

We will enact the error budget policy (see [Document](https://landing.google.com/sre/workbook/chapters/error-budget-policy/))
when any of our objectives has exhausted its error budget.

##### **Clarifications and Caveats**

  - > Request metrics are measured at the Ingress Router (HAProxy). This
    > measurement may fail to accurately measure cases where user
    > requests didn’t reach the Ingress Router.

  - > We only count HTTP 5XX status messages as error codes; everything
    > else is counted as success.

  - > Currently, no measurement were made to verify the SLI on a production
    > cluster, because the relevant metrics are still not available with the
    > current OSD cluster versions. SLO and SLIs may be adjusted when such
    > cluster will be available for our testing.
