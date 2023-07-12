# Backplane Requirements

Process is captured in [SD-ADR-0138: Backplane Access for Managed Services](https://docs.google.com/document/d/1pIPDVluxvxkENBn00-sr4R-k42XbbwZXmJ-l02xMl8w/edit#).

In summary...

* All requirements for backplane access are managed in a subdirectory of this directory.
* SD Architecture is the initial approver for any new requirements.  
* Additional approvers can be added in `OWNERS` files.  SD Architecture must remain an approver.
* All requirements must conform to the [guidelines](../guidelines.md).
* Requirements encompass all access requirements including:
    * conditions for when authorization applies
    * authorization required in-cluster
    * authorization required for cloud accounts
    * authorization required for managed scripts
    * if privilege escalation is required (note if approved guidelines must be updated)

## Directory Structure
* root directory is `docs/backplane/requirements/`
* every persona has a unique sub-directory, i.e. `docs/backplane/requirements/srep` for SRE Platform
* implementation of in-cluster authorization in this repository is in `deploy/backplane/<persona>`, i.e. `deploy/backplane/srep`.
* `OWNERS` files in `docs/backplane/requirements/<persona>` must match `deploy/backplane/<persona>` (PR check enforces this)
* there is no strict naming convention within the requirements directories, create files as it makes sense

## Files
* Each file other than `OWNERS` is markdown (end in `.md`).
* Must include file `00-cloud-console.md` with requirements for cloud access.  This can simply state no access is required.
* Use numeric prefixs to order files for easier reading.
* Template: [10-template.md](10-template.md)
* Example: [srep](srep)