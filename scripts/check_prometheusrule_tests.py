#!/usr/bin/env python3
"""Run PrometheusRule unit tests and check that every alert has a test.

Test files live in tests/prometheusrules/ and use the promtool unit test
format. Each test file tests one PrometheusRule file from deploy/. Because
promtool cannot read a PrometheusRule resource, this script extracts the
rule groups from `spec`, writes them to a temporary file, and points the
test at that file before it runs `promtool test rules`.

The script also checks coverage. Every alert in deploy/ must have at least
one test case where it fires, or be listed in tests/prometheusrules/
exceptions.yaml. Each exception stores a fingerprint of the alert, so a
change to an alert in the exception list fails the check.

See docs/prometheus-rule-tests.md for the full procedure.
"""

import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path
import shutil
import string
import subprocess
import sys
import tempfile
import time

import oyaml as yaml


DEPLOY_DIR = Path("deploy")
TESTS_DIR = Path("tests", "prometheusrules")
EXCEPTIONS_FILE = TESTS_DIR / "exceptions.yaml"
DOCS_FILE = "docs/prometheus-rule-tests.md"
TEST_SUFFIX = ".test.yaml"

# Rule fields that change when an alert fires or how it is routed.
# Annotations are not included, so a text fix in a description does not
# require a new test.
FINGERPRINT_FIELDS = ("expr", "for", "keep_firing_for", "labels")

EXCEPTIONS_HEADER = """\
# Alerts that do not have a unit test yet.
#
# Do not add new alerts to this file. New alerts must have a test.
# Remove an alert from this file when you add its test.
#
# Each value is a fingerprint of the alert's expr, for, keep_firing_for and
# labels. If you change one of these fields, the check fails until you add
# a test and remove the alert from this file.
#
# See docs/prometheus-rule-tests.md.
"""


class RuleFile:
    """A PrometheusRule file from deploy/ and the alerts it defines."""

    def __init__(self, path, spec):
        self.path = path
        self.spec = spec
        self.alerts = defaultdict(list)
        for group in spec.get("groups", []) or []:
            for rule in group.get("rules", []) or []:
                if "alert" in rule:
                    self.alerts[rule["alert"]].append(rule)


def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)


def _find_duplicate_key(node, visited):
    """Return the first key node that repeats a key in its mapping, or None.

    This walks the composed node tree, before `<<` merges are applied. A
    key that overrides a merged value is therefore not a duplicate, but a
    repeated key in any mapping, including an inline merge mapping, is.
    """
    if id(node) in visited:
        return None
    visited.add(id(node))
    children = []
    if isinstance(node, yaml.MappingNode):
        seen = set()
        for key_node, value_node in node.value:
            if key_node.tag != "tag:yaml.org,2002:merge" and isinstance(key_node, yaml.ScalarNode):
                if key_node.value in seen:
                    return key_node
                seen.add(key_node.value)
            children.extend((key_node, value_node))
    elif isinstance(node, yaml.SequenceNode):
        children = node.value
    for child in children:
        found = _find_duplicate_key(child, visited)
        if found is not None:
            return found
    return None


def load_yaml_unique_keys(path):
    """Load YAML like load_yaml, but fail on a duplicate mapping key.

    safe_load keeps the last value of a repeated key, so a test file with
    two `tests:` keys would lose the first block without an error.
    """
    with open(path) as f:
        text = f.read()
    node = yaml.compose(text, Loader=yaml.SafeLoader)
    if node is not None:
        duplicate = _find_duplicate_key(node, set())
        if duplicate is not None:
            raise yaml.constructor.ConstructorError(
                None, None, "found duplicate key '%s'" % duplicate.value, duplicate.start_mark
            )
    return yaml.safe_load(text)


# monitoring.rhobs/v1 is the PrometheusRule CRD of the Observability Operator
# (OBO). It has the same spec format as the Prometheus Operator CRD.
PROMETHEUSRULE_API_VERSIONS = ("monitoring.coreos.com/v1", "monitoring.rhobs/v1")


def is_prometheusrule(doc):
    return (
        isinstance(doc, dict)
        and doc.get("kind") == "PrometheusRule"
        and doc.get("apiVersion") in PROMETHEUSRULE_API_VERSIONS
    )


def find_rule_files(deploy_dir):
    """Return {repo-relative path: RuleFile} for every PrometheusRule in deploy_dir."""
    rule_files = {}
    for root, _, entries in os.walk(deploy_dir):
        for entry in sorted(entries):
            path = Path(root, entry)
            if path.suffix not in (".yaml", ".yml"):
                continue
            try:
                doc = load_yaml(path)
            except yaml.YAMLError:
                # check-prometheusrules.py reports YAML errors.
                continue
            if is_prometheusrule(doc):
                rule_files[path.as_posix()] = RuleFile(path.as_posix(), doc.get("spec", {}) or {})
    return rule_files


def find_test_files(tests_dir):
    if not Path(tests_dir).is_dir():
        return []
    return sorted(p.as_posix() for p in Path(tests_dir).rglob("*" + TEST_SUFFIX))


def expected_test_path(rule_path, deploy_dir=DEPLOY_DIR, tests_dir=TESTS_DIR):
    """Return the test file path for a rule file.

    deploy/a/b/100-x.PrometheusRule.yaml -> tests/prometheusrules/a/b/100-x.PrometheusRule.test.yaml
    """
    relative = Path(rule_path).relative_to(deploy_dir)
    stem = relative.name
    for suffix in (".yaml", ".yml"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            break
    return (Path(tests_dir) / relative.parent / (stem + TEST_SUFFIX)).as_posix()


_WORD_CHARS = frozenset(string.ascii_letters + string.digits + "_:")


def normalize_expr(expr):
    """Collapse whitespace and remove comments outside quoted strings.

    Whitespace between two word tokens (for example `sum by` or `a or b`)
    is kept as one space, because removing it would merge them into a
    single identifier. All other whitespace outside quoted strings is
    removed, so reformatting an expression is not a change. Whitespace
    inside a quoted string is kept, because it changes the meaning.

    A `#` comment runs to the end of the line. It is removed and treated as
    whitespace, so editing a comment is not a change, but code on the next
    line stays separate from the code before the comment.
    """
    out = []
    quote = None
    escaped = False
    pending_space = False
    in_comment = False
    for ch in str(expr):
        if in_comment:
            if ch == "\n":
                in_comment = False
        elif quote:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\" and quote != "`":
                escaped = True
            elif ch == quote:
                quote = None
        elif ch == "#":
            in_comment = True
            pending_space = True
        elif ch.isspace():
            pending_space = True
        else:
            if pending_space and out and out[-1] in _WORD_CHARS and ch in _WORD_CHARS:
                out.append(" ")
            pending_space = False
            if ch in "\"'`":
                quote = ch
            out.append(ch)
    return "".join(out)


def fingerprint(rules):
    """Return a short, stable hash of the fields that define one or more alerting rules."""
    parts = []
    for rule in rules:
        part = {}
        for field in FINGERPRINT_FIELDS:
            if field not in rule:
                continue
            value = rule[field]
            if field == "expr":
                value = normalize_expr(value)
            elif field == "labels":
                value = {str(k): str(v) for k, v in (value or {}).items()}
            else:
                value = str(value)
            part[field] = value
        parts.append(json.dumps(part, sort_keys=True))
    digest = hashlib.sha256("\n".join(sorted(parts)).encode()).hexdigest()
    return digest[:12]


def load_exceptions(path):
    """Return {rule file path: {alert name: fingerprint}}."""
    if not Path(path).exists():
        return {}
    data = load_yaml(path) or {}
    return {str(k): {str(a): str(f) for a, f in (v or {}).items()} for k, v in data.items()}


def write_exceptions(path, exceptions):
    lines = [EXCEPTIONS_HEADER]
    for rule_path in sorted(exceptions):
        alerts = exceptions[rule_path]
        if not alerts:
            continue
        # Write keys and values as JSON strings, which are valid YAML.
        # Unquoted, YAML reads an alert named null as None and a
        # fingerprint such as 012345670123 as an octal integer.
        lines.append("%s:\n" % json.dumps(rule_path))
        for alert in sorted(alerts):
            lines.append("  %s: %s\n" % (json.dumps(alert), json.dumps(alerts[alert])))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        f.write("".join(lines))


class TestFile:
    """A parsed test file and the problems found while reading it."""

    def __init__(self, path, doc, rule_path, errors):
        self.path = path
        self.doc = doc
        self.rule_path = rule_path
        self.errors = errors


def parse_test_file(path, rule_files, tests_dir=TESTS_DIR, deploy_dir=DEPLOY_DIR):
    """Read a test file and validate its rule_files entry and layout."""
    errors = []
    try:
        doc = load_yaml_unique_keys(path)
    except yaml.YAMLError as e:
        return TestFile(path, None, None, ["%s: is not valid YAML: %s" % (path, e)])
    if not isinstance(doc, dict):
        return TestFile(path, None, None, ["%s: must be a YAML mapping in the promtool test format" % path])

    entries = doc.get("rule_files") or []
    if len(entries) != 1:
        errors.append(
            "%s: 'rule_files' must list exactly one PrometheusRule file from %s/ (found %d)"
            % (path, deploy_dir, len(entries))
        )
        return TestFile(path, doc, None, errors)

    rule_path = Path(str(entries[0])).as_posix()
    if rule_path not in rule_files:
        errors.append(
            "%s: 'rule_files' points to '%s', which is not a PrometheusRule file in %s/. "
            "Use the path from the repository root. If you renamed or deleted the rule file, "
            "move or delete this test file too."
            % (path, rule_path, deploy_dir)
        )
        return TestFile(path, doc, None, errors)

    expected = expected_test_path(rule_path, deploy_dir, tests_dir)
    if Path(path).as_posix() != expected:
        errors.append(
            "%s: the test file for '%s' must be at '%s'" % (path, rule_path, expected)
        )
    return TestFile(path, doc, rule_path, errors)


def static_labels(rule):
    """Return the rule's labels whose values are not templates."""
    return {
        str(k): str(v)
        for k, v in (rule.get("labels") or {}).items()
        if "{{" not in str(v)
    }


def rule_matches(rule, exp_labels):
    """Return True when an expected alert's labels could come from this rule."""
    return all(
        k in exp_labels and str(exp_labels[k]) == v for k, v in static_labels(rule).items()
    )


def collect_coverage(test_file, rule_files):
    """Return ({alert names whose every rule fires in at least one case}, [errors]).

    One alert name can have more than one rule, for example a warning and a
    critical. Each rule must match an expected alert in a firing case. An
    expected alert matches a rule when its exp_labels contain the rule's
    labels that are not templates.
    """
    errors = []
    defined = rule_files[test_file.rule_path].alerts
    fired = defaultdict(list)
    for group in test_file.doc.get("tests", []) or []:
        for case in group.get("alert_rule_test", []) or []:
            name = case.get("alertname")
            if name not in defined:
                errors.append(
                    "%s: tests alert '%s', but '%s' does not define it"
                    % (test_file.path, name, test_file.rule_path)
                )
                continue
            for exp in case.get("exp_alerts") or []:
                fired[name].append({str(k): v for k, v in ((exp or {}).get("exp_labels") or {}).items()})
    covered = set()
    for name in sorted(fired):
        missing = [r for r in defined[name] if not any(rule_matches(r, l) for l in fired[name])]
        for rule in missing:
            errors.append(
                "%s: alert '%s' has a rule with labels %s that no firing case matches"
                % (test_file.path, name, json.dumps(static_labels(rule), sort_keys=True))
            )
        if not missing:
            covered.add(name)
    return covered, errors


def check_coverage(rule_files, covered, exceptions):
    """Compare alerts in deploy/ with test coverage and the exception list.

    Returns a dict of problem lists:
      untested:   (rule path, alert) with no test and no exception
      changed:    (rule path, alert, old fingerprint, new fingerprint)
      stale:      (rule path, alert) in exceptions but now tested
      removed:    (rule path, alert) in exceptions but no longer defined
    """
    problems = {"untested": [], "changed": [], "stale": [], "removed": []}
    for rule_path in sorted(rule_files):
        excepted = exceptions.get(rule_path, {})
        for alert in sorted(rule_files[rule_path].alerts):
            is_covered = alert in covered.get(rule_path, set())
            if is_covered:
                if alert in excepted:
                    problems["stale"].append((rule_path, alert))
                continue
            if alert not in excepted:
                problems["untested"].append((rule_path, alert))
                continue
            current = fingerprint(rule_files[rule_path].alerts[alert])
            if current != excepted[alert]:
                problems["changed"].append((rule_path, alert, excepted[alert], current))
    for rule_path in sorted(exceptions):
        defined = rule_files.get(rule_path)
        for alert in sorted(exceptions[rule_path]):
            if defined is None or alert not in defined.alerts:
                problems["removed"].append((rule_path, alert))
    return problems


def build_exceptions(rule_files, covered):
    """Return an exception list with every alert that has no test."""
    exceptions = {}
    for rule_path, rule_file in rule_files.items():
        for alert, rules in rule_file.alerts.items():
            if alert not in covered.get(rule_path, set()):
                exceptions.setdefault(rule_path, {})[alert] = fingerprint(rules)
    return exceptions


def prepare_promtool_input(test_file, rule_files, workdir):
    """Write the extracted rule groups and a rewritten test file to workdir.

    Returns the path of the rewritten test file.
    """
    # Test files in different directories can share a base name, so each
    # test gets its own directory.
    workdir = Path(tempfile.mkdtemp(dir=workdir))
    name = Path(test_file.path).name
    rules_path = Path(workdir, name + ".rules.json")
    with open(rules_path, "w") as f:
        json.dump(rule_files[test_file.rule_path].spec, f)
    doc = dict(test_file.doc)
    doc["rule_files"] = [str(rules_path)]
    test_path = Path(workdir, name)
    with open(test_path, "w") as f:
        yaml.safe_dump(doc, f, default_flow_style=False, sort_keys=False)
    return str(test_path)


def run_promtool(promtool, test_path):
    result = subprocess.run(
        [promtool, "test", "rules", test_path],
        capture_output=True,
        text=True,
    )
    return result.returncode, (result.stdout + result.stderr).strip()


def format_report(problems, exceptions_file=EXCEPTIONS_FILE):
    """Return the failure text for coverage problems, or an empty string."""
    lines = []
    if problems["untested"]:
        lines.append("Alerts without a unit test (%d):" % len(problems["untested"]))
        for rule_path, alert in problems["untested"]:
            lines.append("  '%s' in '%s'" % (alert, rule_path))
            lines.append("    Add a test case where this alert fires to '%s'." % expected_test_path(rule_path))
        lines.append("")
    if problems["changed"]:
        lines.append(
            "Alerts in the exception list that changed (%d):" % len(problems["changed"])
        )
        for rule_path, alert, _, _ in problems["changed"]:
            lines.append("  '%s' in '%s'" % (alert, rule_path))
        lines.append(
            "    You changed the expr, for, keep_firing_for or labels of these alerts."
        )
        lines.append(
            "    An alert in the exception list cannot change without a test."
        )
        lines.append(
            "    Add a test for each alert and remove it from '%s'." % exceptions_file
        )
        lines.append("")
    if problems["stale"]:
        lines.append(
            "Alerts that have a test but are still in the exception list (%d):"
            % len(problems["stale"])
        )
        for rule_path, alert in problems["stale"]:
            lines.append("  '%s' in '%s'" % (alert, rule_path))
        lines.append("    Remove these alerts from '%s'." % exceptions_file)
        lines.append("")
    if problems["removed"]:
        lines.append(
            "Alerts in the exception list that no longer exist (%d):"
            % len(problems["removed"])
        )
        for rule_path, alert in problems["removed"]:
            lines.append("  '%s' in '%s'" % (alert, rule_path))
        lines.append("    Remove these alerts from '%s'." % exceptions_file)
        lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--promtool",
        default=os.environ.get("PROMTOOL", "promtool"),
        help="Path to the promtool binary (default: $PROMTOOL or 'promtool')",
    )
    parser.add_argument(
        "--update-exceptions",
        action="store_true",
        help="Rewrite %s with every alert that has no test, then exit" % EXCEPTIONS_FILE,
    )
    parser.add_argument(
        "--skip-promtool",
        action="store_true",
        help="Only check layout and coverage. Do not run promtool.",
    )
    args = parser.parse_args(argv)

    rule_files = find_rule_files(DEPLOY_DIR)
    test_paths = find_test_files(TESTS_DIR)

    errors = []
    test_files = []
    covered = defaultdict(set)
    for path in test_paths:
        test_file = parse_test_file(path, rule_files)
        errors.extend(test_file.errors)
        if test_file.rule_path is None:
            continue
        alerts, coverage_errors = collect_coverage(test_file, rule_files)
        errors.extend(coverage_errors)
        covered[test_file.rule_path].update(alerts)
        test_files.append(test_file)

    if args.update_exceptions:
        if errors:
            print("Fix these problems before you update the exception list:\n")
            print("\n".join("  " + e for e in errors))
            return 1
        exceptions = build_exceptions(rule_files, covered)
        write_exceptions(EXCEPTIONS_FILE, exceptions)
        print(
            "Wrote %d alerts to '%s'."
            % (sum(len(a) for a in exceptions.values()), EXCEPTIONS_FILE)
        )
        return 0

    failed_tests = []
    if not args.skip_promtool and test_files:
        if shutil.which(args.promtool) is None and not Path(args.promtool).exists():
            print("ERROR: cannot find promtool at '%s'. Set --promtool or $PROMTOOL." % args.promtool)
            return 1
        # Print one line per file as it runs. Some tests take many seconds,
        # and without output the command looks like it has stopped.
        print("Running %d test files with promtool:" % len(test_files), flush=True)
        with tempfile.TemporaryDirectory() as workdir:
            for test_file in test_files:
                started = time.time()
                test_path = prepare_promtool_input(test_file, rule_files, workdir)
                code, output = run_promtool(args.promtool, test_path)
                print(
                    "  %s %s (%.1fs)"
                    % ("ok  " if code == 0 else "FAIL", test_file.path, time.time() - started),
                    flush=True,
                )
                if code != 0:
                    failed_tests.append((test_file, output))
        print("", flush=True)

    problems = check_coverage(rule_files, covered, load_exceptions(EXCEPTIONS_FILE))
    report = format_report(problems)

    alert_count = sum(len(r.alerts) for r in rule_files.values())
    covered_count = sum(len(a) for a in covered.values())

    if errors or failed_tests or report:
        print("PrometheusRule unit tests: FAILED\n")
        if errors:
            print("Problems in test files (%d):" % len(errors))
            for e in errors:
                print("  " + e)
            print("")
        for test_file, output in failed_tests:
            print("promtool test failed: '%s' (tests '%s')" % (test_file.path, test_file.rule_path))
            for line in output.splitlines():
                print("    " + line)
            print("")
        if report:
            print(report)
        print("See %s for how to write and run these tests." % DOCS_FILE)
        return 1

    print(
        "PrometheusRule unit tests: PASSED (%d test files, %d of %d alerts tested)"
        % (len(test_files), covered_count, alert_count)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
