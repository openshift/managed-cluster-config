# hcp-capi-manager-annotator

Pins the core CAPI manager (`cluster-capi-controllers`) for ROSA HCP clusters on
OpenShift **4.19** and **4.20** by setting the
`hypershift.openshift.io/capi-manager-image` annotation on their `HostedCluster`.

## Why

Starting with CAPI v1.11 (OCP 4.21 payloads), the cluster-api project moved to the
`v1beta2` API. A CAPI manager built from a 4.19 or 4.20 payload writes status
through `v1beta1`, and the `v1beta1` to `v1beta2` conversion drops
`status.phase` — leaving it permanently empty — while generating a large volume of
conversion traffic on busy management clusters.

HyperShift already pins a known-good 4.22 `cluster-capi-controllers` image for
payloads below 4.21, but only on `main` / `release-5.0+`:

- `support/backwardcompat/backwardcompat.go` — `GetBackwardCompatibleCAPIImage`
- `docs/content/reference/capi-image-overrides.md`

A 4.19 or 4.20 hosted cluster reconciled by a 4.21 or 4.22 HyperShift operator gets
no such pin, so we apply it from MCC.

## Pinned image

```text
quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:c5c3e36db897fae332284e1a681044cd6997a70e8cb9059f810385352e7575ac
```

This is the `cluster-capi-controllers` component from OCP 4.22 (CAPI 1.13), which
writes `v1beta2` natively. It is the same image HyperShift embeds for the
below-4.21 case, so both paths converge on one build.

The image registers the `--kube-api-qps` and `--clustercache-client-qps` flags that
HyperShift passes for payloads at 4.19 and above, so it starts cleanly for both
4.19 and 4.20 clusters.

## How

`patch.sh` runs on a schedule and, for each hosted cluster:

1. Reads the cluster's `openshiftVersion` label.
2. Asks `should_patch.py` what to do: `pin` below 4.21, `remove` at 4.21 and later,
   `skip` when the version cannot be parsed.
3. Pins or removes the annotation on the `HostedCluster` inside the cluster's
   `ManifestWork` using a **JSON patch on the annotation path only**.

Two safety rules matter here:

- **We never replace the whole `ManifestWork`.** Clusters Service renders that
  object continuously, and a read-modify-write `oc replace` both races with it and
  reverts unrelated changes. Compare with `osd-25821-capa-annotator`, which does
  replace the object.
- **We only remove a value we set.** If the annotation carries any other image, the
  cluster is deliberately pinned by someone else and is left untouched.

There is one CronJob, `capi-manager-annotator`. It lists every managed cluster and
lets `should_patch.py` decide per cluster, so a single job pins 4.19 and 4.20 and
removes the pin everywhere else:

| Cluster version | Action |
|---|---|
| 4.19, 4.20 | pin |
| 4.21 and later | remove our pin, if the value matches the pinned image |
| unparsable | skip |

Handling both directions in one job means an upgrading cluster cannot keep a stale
pin: the same run that stops pinning it also removes the annotation, whether it
moved from 4.20 to 4.21 or was rewritten with a different value.

Re-asserting every five minutes is deliberate: the annotation lives in a rendered
`ManifestWork`, so a Clusters Service re-render can drop it.

## Making changes to scripts

If you change `should_patch.py` or `patch.sh`, regenerate the ConfigMap:

```bash
./generate_configmap.sh
```

## Testing

```bash
python3 -m unittest tests.py
```
