# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Kubernetes/OpenShift configuration management repository** for Red Hat's Managed OpenShift Services (OpenShift Dedicated and ROSA). It maintains static configuration that gets deployed to managed clusters through Red Hat's Hive cluster management system using a GitOps approach.

## Common Development Commands

### Build and Template Generation
```bash
# Generate all templates for all environments (runs in container by default)
make

# Generate OAuth templates from HTML sources
make generate-oauth-templates

# Generate ROSA brand logo configmap
make generate-rosa-brand-logo

# Enforce backplane access rules
make enforce-backplane-rules

# Check links in documentation
make checklinks
```

### Testing and Validation
```bash
# Validate configurations using OpenShift CLI
oc apply --dry-run=client -f /path/to/config.yaml

# Run backplane rules enforcement directly
python scripts/enforce-backplane-rules.py
```

### Manual Script Execution
```bash
# Generate Hive SelectorSyncSet templates
scripts/generate_template.py -t scripts/templates/ -y deploy -d hack/ -r managed-cluster-config

# Generate ACM policy configurations
scripts/generate-policy-config.py

# Generate SubjectPermissions policy configurations
scripts/generate-subjectpermissions-policy-config.py

# Generate CMO (Cluster Monitoring Operator) config
scripts/generate-cmo-config.py
```

## Architecture Overview

### Directory Structure
- **`/deploy`**: Source of truth containing 100+ component directories with raw YAML configurations
  - **`/deploy/acm-policies`**: Generated ACM (Advanced Cluster Management) policy files (50-GENERATED-*.yaml)
  - Each subdirectory must contain a `config.yaml` file (mandatory since OSD-15267)
- **`/hack`**: Generated Hive SelectorSyncSet templates for different environments
  - `00-osd-managed-cluster-config-integration.yaml.tmpl`
  - `00-osd-managed-cluster-config-stage.yaml.tmpl`
  - `00-osd-managed-cluster-config-production.yaml.tmpl`
- **`/scripts`**: Python build automation scripts for template generation and validation
  - Uses Python 3.9 with `oyaml` library
  - All scripts run in containers by default for consistency
- **`/resources`**: Shared resource templates and Prometheus rules
  - `prometheusrules/`: SRE-specific monitoring rules and alerts
  - `sts/`: AWS STS (Security Token Service) configurations
  - `wif/`: Workload Identity Federation configurations
- **`/source/html`**: OAuth login page HTML templates
  - `osd/`: OpenShift Dedicated branding (login.html, providers.html, errors.html)
  - `rosa/`: ROSA branding and logo (rosa-brand-logo.svg)

### Configuration Pattern
Every directory in `/deploy` requires a `config.yaml` file (mandatory). Structure:
```yaml
deploymentMode: "SelectorSyncSet"  # or "Policy"
selectorSyncSet:
  matchLabels: {}  # Optional: adds matchLabels to clusterDeploymentSelector
  matchExpressions:  # Optional: selector matching conditions
    - key: api.openshift.com/product
      operator: NotIn  # or In
      values: ["rosa"]  # Product targeting (rosa, osd)
    - key: hive.openshift.io/cluster-platform
      operator: In
      values: ["aws"]  # Platform targeting (aws, gcp, azure)
  resourceApplyMode: "Sync"  # "Sync" (full sync, removes extra resources) or "Upsert" (only creates/updates)
  matchLabelsApplyMode: "AND"  # "AND" (single SSS) or "OR" (separate SSS per label)
  applyBehavior: null  # Optional: sets SelectorSyncSet's applyBehavior (see Hive docs)

# Optional: Policy configuration for ACM policy generation
policy:
  destination: "acm-policies"  # Enable ACM policy generation
  complianceType: "mustonlyhave"  # or "musthave", "mustnothave"
  metadataComplianceType: "musthave"  # Compliance type for metadata
```

**Real-world example** (version-specific deployment):
```yaml
deploymentMode: "SelectorSyncSet"
selectorSyncSet:
  resourceApplyMode: Sync
  matchExpressions:
  - key: hive.openshift.io/version
    operator: In
    values: ["4.14.0-rc.3", "4.14.0-rc.4", "4.15.0-ec.0"]
```

### Build Process Flow
```
1. Source files (/deploy/*.yaml + config.yaml)
2. OAuth template generation (source/html → deploy/*-oauth-templates-*)
3. Policy generation (config.yaml with policy.destination → deploy/acm-policies/50-GENERATED-*)
4. SelectorSyncSet generation (scripts/generate_template.py → hack/00-osd-managed-cluster-config-*.yaml.tmpl)
5. Hive applies templates to target clusters based on selectors
```

**Container-based build** (default):
- All builds run in UBI8 Python 3.9 containers for consistency
- PolicyGenerator binary (v1.12.4) downloaded during build
- SELinux volume mount flags handled automatically (`:z` on Linux, none on macOS with Podman)

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
Configurations use selector-based targeting with matchLabels and matchExpressions:

**Common selector keys:**
- `api.openshift.com/product`: Product type
  - Values: `rosa`, `osd`
  - Use `NotIn: ["rosa"]` for OSD-only, `In: ["rosa"]` for ROSA-only
- `hive.openshift.io/cluster-platform`: Cloud platform
  - Values: `aws`, `gcp`, `azure`
- `api.openshift.com/fedramp`: FedRAMP compliance level
  - Values: `true`, `moderate`, `high`
- `hive.openshift.io/version`: OpenShift version
  - Values: Specific versions like `4.14.0-rc.3`, `4.15.0-ec.0`
- `ext-hypershift.openshift.io/cluster-type`: Hypershift cluster type
  - Values: `management-cluster`, `service-cluster`, `hosted-cluster`

**Example selector combinations:**
```yaml
# ROSA on AWS only
matchExpressions:
  - key: api.openshift.com/product
    operator: In
    values: ["rosa"]
  - key: hive.openshift.io/cluster-platform
    operator: In
    values: ["aws"]

# OSD (excluding ROSA) on any platform
matchExpressions:
  - key: api.openshift.com/product
    operator: NotIn
    values: ["rosa"]
```

### Resource Apply Modes
- **Sync**: Full synchronization - removes resources not in template
- **Upsert**: Only creates/updates resources, never removes

## Development Workflow

### Adding a New SelectorSyncSet
1. **Create directory** under `/deploy` with descriptive name
2. **Add YAML manifests** for Kubernetes resources
3. **Create config.yaml** with appropriate selectors and apply mode
4. **Run `make`** to generate templates
5. **Validate** the generated template in `/hack`
6. **Test in integration** before promoting to production

### Adding an ACM Policy
**Option 1 - Convert existing manifest to policy:**
1. Add `policy.destination: "acm-policies"` to existing object's `config.yaml`
2. Run `make` to generate policy in `deploy/acm-policies/50-GENERATED-*.yaml`

**Option 2 - Create new policy-only manifest:**
1. Create new directory under `/deploy`
2. Add manifests and `config.yaml` with `policy.destination: "acm-policies"`
3. Set `deploymentMode: "Policy"` if you want ONLY policy deployment (no SelectorSyncSet)
4. Run `make` to generate policy

### Updating OAuth Templates
1. **Edit HTML** files in `source/html/osd/` or `source/html/rosa/`
2. **Run `make generate-oauth-templates`** to regenerate secrets
3. **Run `make`** to update full templates
4. Templates are automatically split into separate secrets (login, providers, errors) to avoid size limits

### Standard Development Flow
1. **Modify configurations** in `/deploy` directories
2. **Update config.yaml** if changing deployment targeting
3. **Run `make`** to generate templates and verify build
4. **Test in integration environment** before promoting to production
5. **Follow team ownership** patterns defined in OWNERS files

## Important Constraints

- **Mandatory config.yaml**: Every `/deploy` subdirectory must have a `config.yaml` file (enforced since OSD-15267)
  - Build will fail with error if missing: `ERROR : Missing config.yaml for resource defined in deploy/...`
  - Configuration is NOT inherited by subdirectories
- **Generated files**: Never manually edit these files as they're auto-generated:
  - `hack/00-osd-managed-cluster-config-*.yaml.tmpl` (generated from deploy/)
  - `deploy/acm-policies/50-GENERATED-*.yaml` (generated by PolicyGenerator)
  - `deploy/*-oauth-templates-*/` (generated from source/html/)
- **Container builds**: All builds run in containers for consistency (Docker/Podman)
- **Validation**: Configurations must pass OpenShift CLI dry-run validation
- **GitHub Actions**: Template generation runs automatically on push
- **Code review**: Changes affecting production require team review per OWNERS files
- **OAuth templates**: HTML files are converted to Kubernetes secrets, one per file (login, providers, errors) to avoid annotation size limits

## Dependencies

- **Python 3.9** with `oyaml` library
- **OpenShift CLI (oc)** for validation
- **Container runtime** (Docker/Podman)
- **Red Hat PolicyGenerator** for ACM policy creation