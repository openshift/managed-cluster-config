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

## Approval semantics

[Prow OWNERS filters](https://www.kubernetes.dev/docs/guide/owners/#filters)
use Go regular expressions on paths relative to their OWNERS file. Matching
approvers are additive with inherited owners; they are not a requirement for
approval by every listed team. A mixed payload-and-selector PR still needs an
existing approver for the selector. An authorized PR author may `/approve`
their own changes; `/lgtm` is a separate review mechanism, not a restriction
enforced by these OWNERS filters.
