#!/usr/bin/env python

"""
Post-processing script to add annotations to Policy resources and tolerations to Placement resources.
This script is needed because:
1. The PolicyGenerator tool doesn't support tolerations in the placement field of the template
2. The description annotation needs to be explicitly set to an empty string on Policy resources
"""

import oyaml as yaml
import os
import sys
from pathlib import Path

PLACEMENT_TOLERATIONS = [
    {
        "key": "cluster.open-cluster-management.io/unavailable",
        "operator": "Exists"
    },
    {
        "key": "cluster.open-cluster-management.io/unreachable",
        "operator": "Exists"
    }
]

POLICY_DESCRIPTION_ANNOTATION = "policy.open-cluster-management.io/description"
POLICY_DESCRIPTION_VALUE = ""

def add_annotations_and_tolerations(policy_file):
    """Add annotations to Policy resources and tolerations to Placement resources."""
    try:
        with open(policy_file, 'r') as f:
            documents = list(yaml.safe_load_all(f))
    except Exception as e:
        print(f"Error reading {policy_file}: {e}", file=sys.stderr)
        return False

    modified = False
    for doc in documents:
        if not doc:
            continue
            
        # Add description annotation to Policy resources
        if doc.get('kind') == 'Policy':
            if 'metadata' not in doc:
                doc['metadata'] = {}
            if 'annotations' not in doc['metadata']:
                doc['metadata']['annotations'] = {}
            # Only add if not already present
            if POLICY_DESCRIPTION_ANNOTATION not in doc['metadata']['annotations']:
                doc['metadata']['annotations'][POLICY_DESCRIPTION_ANNOTATION] = POLICY_DESCRIPTION_VALUE
                modified = True
        
        # Add tolerations to Placement resources
        elif doc.get('kind') == 'Placement':
            if 'spec' not in doc:
                doc['spec'] = {}
            # Only add if not already present
            if 'tolerations' not in doc['spec']:
                doc['spec']['tolerations'] = PLACEMENT_TOLERATIONS
                modified = True

    if modified:
        try:
            with open(policy_file, 'w') as f:
                yaml.dump_all(documents, f, default_flow_style=False)
            return True
        except Exception as e:
            print(f"Error writing {policy_file}: {e}", file=sys.stderr)
            return False

    return True

def main():
    """Process all generated policy files."""
    policy_dir = Path("deploy/acm-policies")
    
    if not policy_dir.exists():
        print(f"Error: {policy_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    # Process all 50-GENERATED-*.Policy.yaml files
    policy_files = list(policy_dir.glob("50-GENERATED-*.Policy.yaml"))
    
    if not policy_files:
        print(f"No policy files found in {policy_dir}")
        return

    failed = []
    for policy_file in sorted(policy_files):
        if not add_annotations_and_tolerations(str(policy_file)):
            failed.append(str(policy_file))
            print(f"Failed to process {policy_file}")
        else:
            print(f"Processed {policy_file.name}")

    if failed:
        print(f"\nFailed files: {failed}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
