# Scoped FedRAMP ownership

The `srep-functional-team-fedramp` alias can review and approve the payload
files explicitly matched by the `OWNERS` filters in:

- `deploy/osd-fedramp-machineconfig/reg-trust/`: the master and worker registry
  trust manifests in `int/`, `stg/`, and `prod/`.
- `deploy/osd-avo-resources/fedramp-vpc-endpoints/`: the VPC endpoint manifests
  in `us-gov-east-1/` and `us-gov-west-1/`.
- `deploy/sre-prometheus/fedramp/`: the two top-level Prometheus rules and
  the `hive-prod/` heartbeat rule.

Each payload directory has its own `config.yaml` requiring
`api.openshift.com/fedramp` to be `"true"`. Deployment configuration is not
inherited from parent directories. The anchored, explicit filename filters do
not delegate `config.yaml`, `OWNERS`, other control files, or new payload paths.
Changing targeting, extending this delegation, or adding a deployment still
requires the existing broader approvers. No parent ownership is disabled;
existing approvers and reviewers remain eligible. People already authorized
through another alias or an existing OWNERS entry retain that authority.

This grant does not include other FedRAMP directories, shared or commercial
configuration, `resources/`, generator scripts, root `OWNERS` or
`OWNERS_ALIASES`, or the generated `hack/` templates.

## Generated-template approval remains a separate step

`scripts/generate_template.py` combines deployment payloads and selectors into
`hack/00-osd-managed-cluster-config-{integration,stage,production}.yaml.tmpl`.
Changing a delegated payload can therefore still require broader approval for
its regenerated templates. Generate these files using the repository's build
workflow; do not edit them manually.

The required [`ci/prow/pr-check`](https://github.com/openshift/release/blob/master/core-services/prow/02_config/openshift/managed-cluster-config/_prowconfig.yaml)
runs [`hack/pr_check.sh`](../hack/pr_check.sh), which regenerates templates with
`IN_CONTAINER=true make` but compares their **sorted lines**. That comparison
discards YAML ordering and structure: a manual reassignment of existing lines
between resources can preserve the sorted contents. The GitHub Actions
generation workflow also does not establish an exact, required parity check.
Consequently, source ownership plus the current checks does not justify
delegating approval of entire shared generated files. Those files retain their
existing approvers until an enforced check can rule out generated-only changes
to unrelated configuration. This is a remaining approval bottleneck, not a
claim of complete commercial isolation.

## Approval semantics

[Prow OWNERS filters](https://www.kubernetes.dev/docs/guide/owners/#filters)
use Go regular expressions on paths relative to their OWNERS file. Matching
approvers are additive with inherited owners; they are not a requirement for
approval by every listed team. A mixed payload-and-selector PR still needs an
existing approver for the selector. An authorized PR author may `/approve`
their own changes; `/lgtm` is a separate review mechanism, not a restriction
enforced by these OWNERS filters.
