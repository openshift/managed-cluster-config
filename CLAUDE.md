# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Kubernetes/OpenShift configuration management repository** for Red Hat's Managed OpenShift Services (OpenShift Dedicated and ROSA). It maintains static configuration that gets deployed to managed clusters through Red Hat's Hive cluster management system using a GitOps approach.

## Common Development Commands

### Build and Template Generation
```bash
# Generate all templates for all environments
make

# Generate templates for specific environment
make integration  # or 'stage', 'production'

# Run in container (recommended for consistency)
make container-build

# Generate ACM policies
make policies

# Validate all configurations
make validate
```

### Testing and Validation
```bash
# Validate configurations using OpenShift CLI
oc apply --dry-run=client -f /path/to/config.yaml

# Run backplane rules enforcement
python scripts/enforce-backplane-rules.py

# Check links in documentation
make check-links
```

## Architecture Overview

### Directory Structure
- **`/deploy`**: Source of truth containing 100+ component directories with raw YAML configurations
- **`/hack`**: Generated Hive templates for different environments (integration/stage/production)
- **`/scripts`**: Python build automation scripts for template generation and validation
- **`/resources`**: Shared resource templates and Prometheus rules
- **`/source`**: HTML templates for OAuth branding customization

### Configuration Pattern
Every directory in `/deploy` requires a `config.yaml` file with structure:
```yaml
deploymentMode: "SelectorSyncSet"  # or "Policy"
selectorSyncSet:
  matchExpressions:
    - key: api.openshift.com/product
      operator: NotIn  # or In
      values: ["rosa"]  # Product targeting
  resourceApplyMode: "Sync"  # or "Upsert"
```

### Build Process Flow
```
Raw configs (/deploy) → Template Generation → Environment templates (/hack) → Hive Deployment
```

## Key Technical Details

### Template Generation
- Uses Python with `oyaml` library for YAML processing
- Converts raw configurations into Hive SelectorSyncSet templates
- Supports environment-specific customization (integration/stage/production)
- Generates both deployment templates and ACM policies from same source

### Multi-Product Support
- **OpenShift Dedicated (OSD)**: Standard managed OpenShift
- **ROSA**: Red Hat OpenShift Service on AWS with specific configurations
- **FedRAMP**: Government compliance configurations
- **Hypershift**: Hosted control plane support

### Deployment Targeting
Configurations use selector-based targeting:
- `api.openshift.com/product`: Product type (rosa, osd)
- `hive.openshift.io/cluster-platform`: Cloud platform (aws, gcp, azure)
- `api.openshift.com/fedramp`: FedRAMP compliance level

### Resource Apply Modes
- **Sync**: Full synchronization - removes resources not in template
- **Upsert**: Only creates/updates resources, never removes

## Development Workflow

1. **Modify configurations** in `/deploy` directories
2. **Update config.yaml** if changing deployment targeting
3. **Run `make validate`** to check configuration syntax
4. **Run `make`** to generate templates and verify build
5. **Test in integration environment** before promoting to production
6. **Follow team ownership** patterns defined in OWNERS files

## Important Constraints

- All builds run in containers for consistency
- Every `/deploy` subdirectory must have a `config.yaml` file
- Template generation is automatic via GitHub Actions on push
- Configurations must pass OpenShift CLI validation
- Changes affecting production require team review per OWNERS files
- Never manually modify files with path `hack/00-osd-managed-cluster-config*.yaml.tmpl` or `deploy/acm-policies/50-GENERATED-*.yaml`, as they're generated with `make generate`.

## Dependencies

- **Python 3.9** with `oyaml` library
- **OpenShift CLI (oc)** for validation
- **Container runtime** (Docker/Podman)
- **Red Hat PolicyGenerator** for ACM policy creation