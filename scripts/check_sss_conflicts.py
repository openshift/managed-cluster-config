#!/usr/bin/env python3

import oyaml as yaml
import os
import sys
import argparse
from collections import defaultdict
from pathlib import Path


def normalize_selector(match_labels, match_expressions):
    """Create canonical string representation of selector for comparison.

    Args:
        match_labels: dict of label key-value pairs
        match_expressions: list of expression dicts with key, operator, values

    Returns:
        str: Normalized selector string
    """
    parts = []

    if match_labels:
        sorted_labels = sorted(match_labels.items())
        label_str = ','.join(f"{k}={v}" for k, v in sorted_labels)
        parts.append(f"matchLabels={{{label_str}}}")
    else:
        parts.append("matchLabels={}")

    if match_expressions:
        sorted_exprs = sorted(
            match_expressions,
            key=lambda e: (e.get('key', ''), e.get('operator', ''), tuple(e.get('values', [])))
        )
        expr_strs = []
        for expr in sorted_exprs:
            key = expr.get('key', '')
            op = expr.get('operator', '')
            values = ','.join(str(v) for v in expr.get('values', []))
            expr_strs.append(f"{{key:{key},op:{op},values:{values}}}")
        parts.append(f"matchExpressions=[{','.join(expr_strs)}]")
    else:
        parts.append("matchExpressions=[]")

    return ' '.join(parts)


def selectors_equal(selector1, selector2):
    """Compare two selectors for equality.

    Args:
        selector1: dict with 'match_labels' and 'match_expressions'
        selector2: dict with 'match_labels' and 'match_expressions'

    Returns:
        bool: True if selectors are identical
    """
    norm1 = normalize_selector(selector1['match_labels'], selector1['match_expressions'])
    norm2 = normalize_selector(selector2['match_labels'], selector2['match_expressions'])
    return norm1 == norm2


def parse_config(config_path):
    """Parse config.yaml and extract selector info.

    Returns:
        dict or None: {
            'deployment_mode': str,
            'match_labels': dict,
            'match_expressions': list
        }
    """
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)

        if not config:
            return None

        deployment_mode = config.get('deploymentMode', '')
        if deployment_mode != 'SelectorSyncSet':
            return None

        sss_config = config.get('selectorSyncSet', {})

        return {
            'deployment_mode': deployment_mode,
            'match_labels': sss_config.get('matchLabels', {}),
            'match_expressions': sss_config.get('matchExpressions', [])
        }
    except Exception as e:
        print(f"Warning: Error parsing {config_path}: {e}", file=sys.stderr)
        return None


def extract_resources(sss_dir):
    """Extract all resources from YAML files in SSS directory.

    Args:
        sss_dir: Path to SSS directory

    Returns:
        list: [(namespace, name, kind), ...]
    """
    resources = []

    try:
        for filename in os.listdir(sss_dir):
            if not filename.endswith('.yaml') or filename == 'config.yaml':
                continue

            filepath = os.path.join(sss_dir, filename)

            try:
                with open(filepath, 'r') as f:
                    for doc in yaml.safe_load_all(f):
                        if not doc or not isinstance(doc, dict):
                            continue

                        kind = doc.get('kind')
                        metadata = doc.get('metadata', {})
                        name = metadata.get('name')
                        namespace = metadata.get('namespace', '')

                        if kind and name:
                            resources.append((namespace, name, kind))
            except Exception as e:
                print(f"Warning: Error parsing {filepath}: {e}", file=sys.stderr)

    except Exception as e:
        print(f"Warning: Error reading directory {sss_dir}: {e}", file=sys.stderr)

    return resources


def main():
    parser = argparse.ArgumentParser(
        description='Check for SelectorSyncSet resource conflicts with identical selectors'
    )
    parser.add_argument(
        '--deploy-dir',
        default='deploy',
        help='Deploy directory to check (default: deploy/)'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Show detailed parsing info'
    )

    args = parser.parse_args()

    if not os.path.isdir(args.deploy_dir):
        print(f"Error: Deploy directory '{args.deploy_dir}' not found", file=sys.stderr)
        sys.exit(1)

    print("Checking SelectorSyncSet resource conflicts...")
    if args.verbose:
        print(f"Scanning directory: {args.deploy_dir}")

    # resource_id (namespace/name/kind) → list of {sss_path, selector}
    resource_map = defaultdict(list)

    # Walk the deploy directory
    for root, dirs, files in os.walk(args.deploy_dir):
        if 'config.yaml' not in files:
            continue

        config_path = os.path.join(root, 'config.yaml')

        if args.verbose:
            print(f"Processing: {config_path}")

        config = parse_config(config_path)
        if not config:
            if args.verbose:
                print(f"  Skipped (not a SelectorSyncSet)")
            continue

        selector = {
            'match_labels': config['match_labels'],
            'match_expressions': config['match_expressions']
        }

        resources = extract_resources(root)

        if args.verbose:
            print(f"  Found {len(resources)} resource(s)")

        for namespace, name, kind in resources:
            resource_id = f"{namespace}/{name}/{kind}"
            resource_map[resource_id].append({
                'sss_path': root,
                'selector': selector
            })

    # Check for conflicts
    conflicts = []
    info_messages = []

    for resource_id, sss_list in resource_map.items():
        if len(sss_list) <= 1:
            continue

        # Multiple SSSs apply this resource
        # Check if any have identical selectors
        for i in range(len(sss_list)):
            for j in range(i + 1, len(sss_list)):
                if selectors_equal(sss_list[i]['selector'], sss_list[j]['selector']):
                    conflicts.append({
                        'resource_id': resource_id,
                        'sss_paths': [sss_list[i]['sss_path'], sss_list[j]['sss_path']],
                        'selector': normalize_selector(
                            sss_list[i]['selector']['match_labels'],
                            sss_list[i]['selector']['match_expressions']
                        )
                    })

        # If verbose, also note resources with different selectors
        if args.verbose:
            has_different = False
            for i in range(len(sss_list)):
                for j in range(i + 1, len(sss_list)):
                    if not selectors_equal(sss_list[i]['selector'], sss_list[j]['selector']):
                        has_different = True
                        break
                if has_different:
                    break

            if has_different:
                info_messages.append({
                    'resource_id': resource_id,
                    'sss_list': sss_list
                })

    # Report conflicts
    if conflicts:
        print()
        for conflict in conflicts:
            print(f"ERROR: Resource conflict with identical selectors")
            print(f"  Resource: {conflict['resource_id']}")
            print(f"  Conflicting SSSs:")
            for sss_path in conflict['sss_paths']:
                print(f"    - {sss_path}")
            print(f"  Selector: {conflict['selector']}")
            print()

    # Report info messages if verbose
    if args.verbose and info_messages:
        print()
        for info in info_messages:
            print(f"INFO: Resource applied by multiple SSSs with different selectors (OK)")
            print(f"  Resource: {info['resource_id']}")
            print(f"  SSSs:")
            for sss_info in info['sss_list']:
                selector_str = normalize_selector(
                    sss_info['selector']['match_labels'],
                    sss_info['selector']['match_expressions']
                )
                print(f"    - {sss_info['sss_path']}")
                print(f"      Selector: {selector_str}")
            print()

    # Summary
    print(f"Summary: {len(conflicts)} conflict(s) found")

    if conflicts:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
