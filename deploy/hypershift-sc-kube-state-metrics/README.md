# Hypershift SC kube-state-metrics (cert-manager Challenges)

Same custom-resource-state KSM pattern as `deploy/hypershift-kube-state-metrics`, but **SelectorSyncSet to service-cluster only**.

ROSAENG-3733 RHOBS alerts `CertManagerChallengeQueueSaturation` / `QueueFull` need `certmanager_challenge_cr_info` on **SC** (ingress ACME). The existing SSS is `management-cluster` only (#2802).

This stack only watches `acme.cert-manager.io` Challenges so we do not ship CAPI/NodePool/Velero scrapes onto SCs.
