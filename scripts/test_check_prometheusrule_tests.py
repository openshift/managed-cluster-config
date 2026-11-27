#!/usr/bin/env python3
"""Unit tests for the PrometheusRule unit test runner and coverage guard."""

import contextlib
import copy
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import textwrap
import unittest

import oyaml as yaml

import check_prometheusrule_tests as cpt


RULE_FILE = "deploy/sre-prometheus/100-example.PrometheusRule.yaml"
TEST_FILE = "tests/prometheusrules/sre-prometheus/100-example.PrometheusRule.test.yaml"

RULE_DOC = {
    "apiVersion": "monitoring.coreos.com/v1",
    "kind": "PrometheusRule",
    "metadata": {"name": "example", "namespace": "openshift-monitoring"},
    "spec": {
        "groups": [
            {
                "name": "example",
                "rules": [
                    {"record": "example:up:sum", "expr": "sum(up)"},
                    {
                        "alert": "ExampleDownSRE",
                        "expr": "up{job=\"example\"} == 0",
                        "for": "5m",
                        "labels": {"severity": "warning", "namespace": "openshift-monitoring"},
                        "annotations": {"summary": "Example is down."},
                    },
                    {
                        "alert": "ExampleSlowSRE",
                        "expr": "example_latency_seconds > 1",
                        "labels": {"severity": "info", "namespace": "openshift-monitoring"},
                    },
                ],
            }
        ]
    },
}


def firing_case(alertname):
    return {
        "eval_time": "10m",
        "alertname": alertname,
        "exp_alerts": [{"exp_labels": {"severity": "warning", "namespace": "openshift-monitoring"}}],
    }


def two_rule_doc():
    """RULE_DOC with a second, critical rule for ExampleDownSRE."""
    doc = copy.deepcopy(RULE_DOC)
    rules = doc["spec"]["groups"][0]["rules"]
    critical = copy.deepcopy(rules[1])
    critical["for"] = "1h"
    critical["labels"]["severity"] = "critical"
    rules.insert(2, critical)
    return doc


def silent_case(alertname):
    return {"eval_time": "1m", "alertname": alertname, "exp_alerts": []}


def test_doc(cases, rule_file=RULE_FILE):
    return {
        "rule_files": [rule_file],
        "evaluation_interval": "1m",
        "tests": [{"interval": "1m", "input_series": [], "alert_rule_test": cases}],
    }


class RepoTestCase(unittest.TestCase):
    """Run each test in an empty temporary directory that acts as the repo root."""

    def setUp(self):
        self._old_cwd = os.getcwd()
        self._tmp = tempfile.TemporaryDirectory()
        os.chdir(self._tmp.name)

    def tearDown(self):
        os.chdir(self._old_cwd)
        self._tmp.cleanup()

    def write(self, path, content):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            if isinstance(content, str):
                f.write(content)
            else:
                yaml.safe_dump(content, f, default_flow_style=False)


class ExpectedTestPathTests(unittest.TestCase):
    def test_mirrors_deploy_path_and_replaces_extension(self):
        self.assertEqual(cpt.expected_test_path(RULE_FILE), TEST_FILE)

    def test_handles_yml_extension(self):
        self.assertEqual(
            cpt.expected_test_path("deploy/a/b/rules.yml"),
            "tests/prometheusrules/a/b/rules.test.yaml",
        )

    def test_handles_names_without_prometheusrule_in_them(self):
        self.assertEqual(
            cpt.expected_test_path("deploy/sre-prometheus/100-kube-apiserver-missing-on-node.yaml"),
            "tests/prometheusrules/sre-prometheus/100-kube-apiserver-missing-on-node.test.yaml",
        )


class FingerprintTests(unittest.TestCase):
    base = {
        "alert": "A",
        "expr": "up == 0",
        "for": "5m",
        "labels": {"severity": "warning"},
        "annotations": {"summary": "s"},
    }

    def changed(self, **fields):
        rule = dict(self.base)
        rule.update(fields)
        return rule

    def test_is_stable(self):
        self.assertEqual(cpt.fingerprint([self.base]), cpt.fingerprint([dict(self.base)]))

    def test_ignores_whitespace_in_expr(self):
        self.assertEqual(
            cpt.fingerprint([self.base]),
            cpt.fingerprint([self.changed(expr="up\n  ==   0\n")]),
        )

    def test_ignores_whitespace_around_parentheses_and_operators(self):
        self.assertEqual(
            cpt.fingerprint([self.changed(expr="sum(x) > 1")]),
            cpt.fingerprint([self.changed(expr="sum( x )   >   1")]),
        )

    def test_keeps_whitespace_inside_quoted_strings(self):
        self.assertNotEqual(
            cpt.fingerprint([self.changed(expr='x{reason="a b"} > 0')]),
            cpt.fingerprint([self.changed(expr='x{reason="ab"} > 0')]),
        )

    def test_keeps_whitespace_between_word_tokens(self):
        self.assertNotEqual(
            cpt.fingerprint([self.changed(expr="foo or bar")]),
            cpt.fingerprint([self.changed(expr="fooorbar")]),
        )

    def test_collapses_whitespace_between_word_tokens_to_one_space(self):
        self.assertEqual(cpt.normalize_expr("sum\n  by   (job) (x)"), "sum by(job)(x)")

    def test_comment_ends_at_newline(self):
        self.assertNotEqual(
            cpt.fingerprint([self.changed(expr="up # note\n > 0")]),
            cpt.fingerprint([self.changed(expr="up # note > 0")]),
        )

    def test_ignores_comment_text(self):
        self.assertEqual(
            cpt.fingerprint([self.changed(expr="up # old note\n > 0")]),
            cpt.fingerprint([self.changed(expr="up # new note\n > 0")]),
        )

    def test_keeps_hash_inside_quoted_strings(self):
        self.assertEqual(cpt.normalize_expr('x{a="b # c"} > 0'), 'x{a="b # c"}>0')

    def test_handles_escaped_quotes_in_strings(self):
        self.assertEqual(
            cpt.normalize_expr('x{a="say \\"hi there\\""} > 0'),
            'x{a="say \\"hi there\\""}>0',
        )

    def test_ignores_annotations(self):
        self.assertEqual(
            cpt.fingerprint([self.base]),
            cpt.fingerprint([self.changed(annotations={"summary": "fixed typo"})]),
        )

    def test_changes_when_expr_changes(self):
        self.assertNotEqual(
            cpt.fingerprint([self.base]), cpt.fingerprint([self.changed(expr="up == 1")])
        )

    def test_changes_when_for_changes(self):
        self.assertNotEqual(
            cpt.fingerprint([self.base]), cpt.fingerprint([self.changed(**{"for": "10m"})])
        )

    def test_changes_when_keep_firing_for_is_added(self):
        self.assertNotEqual(
            cpt.fingerprint([self.base]),
            cpt.fingerprint([self.changed(keep_firing_for="5m")]),
        )

    def test_changes_when_labels_change(self):
        self.assertNotEqual(
            cpt.fingerprint([self.base]),
            cpt.fingerprint([self.changed(labels={"severity": "critical"})]),
        )

    def test_rule_order_does_not_matter_for_repeated_alert_names(self):
        other = self.changed(labels={"severity": "critical"})
        self.assertEqual(
            cpt.fingerprint([self.base, other]), cpt.fingerprint([other, self.base])
        )


class FindRuleFilesTests(RepoTestCase):
    def test_finds_only_prometheusrules(self):
        self.write(RULE_FILE, RULE_DOC)
        self.write("deploy/other/configmap.yaml", {"apiVersion": "v1", "kind": "ConfigMap"})
        self.write("deploy/other/notes.txt", "not yaml")
        rule_files = cpt.find_rule_files("deploy")
        self.assertEqual(list(rule_files), [RULE_FILE])
        self.assertEqual(
            sorted(rule_files[RULE_FILE].alerts), ["ExampleDownSRE", "ExampleSlowSRE"]
        )

    def test_finds_observability_operator_prometheusrules(self):
        doc = json.loads(json.dumps(RULE_DOC))
        doc["apiVersion"] = "monitoring.rhobs/v1"
        self.write(RULE_FILE, doc)
        self.assertEqual(list(cpt.find_rule_files("deploy")), [RULE_FILE])

    def test_ignores_other_api_versions(self):
        doc = json.loads(json.dumps(RULE_DOC))
        doc["apiVersion"] = "example.com/v1"
        self.write(RULE_FILE, doc)
        self.assertEqual(cpt.find_rule_files("deploy"), {})

    def test_groups_rules_with_the_same_alert_name(self):
        doc = json.loads(json.dumps(RULE_DOC))
        rules = doc["spec"]["groups"][0]["rules"]
        rules.append(dict(rules[1], labels={"severity": "critical"}))
        self.write(RULE_FILE, doc)
        rule_files = cpt.find_rule_files("deploy")
        self.assertEqual(len(rule_files[RULE_FILE].alerts["ExampleDownSRE"]), 2)


class ParseTestFileTests(RepoTestCase):
    def setUp(self):
        super().setUp()
        self.write(RULE_FILE, RULE_DOC)
        self.rule_files = cpt.find_rule_files("deploy")

    def test_valid_file_has_no_errors(self):
        self.write(TEST_FILE, test_doc([firing_case("ExampleDownSRE")]))
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertEqual(parsed.errors, [])
        self.assertEqual(parsed.rule_path, RULE_FILE)

    def test_requires_exactly_one_rule_file(self):
        doc = test_doc([])
        doc["rule_files"] = [RULE_FILE, RULE_FILE]
        self.write(TEST_FILE, doc)
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertIsNone(parsed.rule_path)
        self.assertIn("exactly one", parsed.errors[0])

    def test_reports_missing_rule_file(self):
        self.write(TEST_FILE, test_doc([], rule_file="deploy/sre-prometheus/gone.yaml"))
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertIsNone(parsed.rule_path)
        self.assertIn("not a PrometheusRule file", parsed.errors[0])

    def test_reports_wrong_location(self):
        wrong = "tests/prometheusrules/elsewhere.test.yaml"
        self.write(wrong, test_doc([]))
        parsed = cpt.parse_test_file(wrong, self.rule_files)
        self.assertEqual(parsed.rule_path, RULE_FILE)
        self.assertIn(TEST_FILE, parsed.errors[0])

    def test_reports_invalid_yaml(self):
        self.write(TEST_FILE, "rule_files: [\n")
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertIn("not valid YAML", parsed.errors[0])

    def test_reports_duplicate_keys(self):
        self.write(
            TEST_FILE,
            "rule_files: [%s]\ntests: []\ntests: []\n" % RULE_FILE,
        )
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertIn("not valid YAML", parsed.errors[0])
        self.assertIn("duplicate key 'tests'", parsed.errors[0])

    def test_reports_duplicate_keys_inside_merge_source(self):
        self.write(
            TEST_FILE,
            "rule_files: [%s]\n<<: {tests: [{interval: 1m}], tests: []}\n" % RULE_FILE,
        )
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertIn("duplicate key 'tests'", parsed.errors[0])

    def test_allows_nested_merge_overrides(self):
        self.write(
            TEST_FILE,
            "rule_files: [%s]\ntests:\n- &base {interval: 1m}\n- &middle\n  <<: *base\n"
            "  interval: 5m\n- <<: *middle\n" % RULE_FILE,
        )
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertEqual(parsed.errors, [])

    def test_allows_yaml_merge_keys(self):
        self.write(
            TEST_FILE,
            "rule_files: [%s]\ntests:\n- &base {interval: 1m}\n- <<: *base\n  interval: 5m\n"
            % RULE_FILE,
        )
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        self.assertEqual(parsed.errors, [])


class CollectCoverageTests(RepoTestCase):
    def setUp(self):
        super().setUp()
        self.write(RULE_FILE, RULE_DOC)
        self.rule_files = cpt.find_rule_files("deploy")

    def coverage(self, cases):
        self.write(TEST_FILE, test_doc(cases))
        parsed = cpt.parse_test_file(TEST_FILE, self.rule_files)
        return cpt.collect_coverage(parsed, self.rule_files)

    def test_firing_case_counts_as_coverage(self):
        covered, errors = self.coverage([silent_case("ExampleDownSRE"), firing_case("ExampleDownSRE")])
        self.assertEqual(covered, {"ExampleDownSRE"})
        self.assertEqual(errors, [])

    def test_only_silent_cases_do_not_count(self):
        covered, errors = self.coverage([silent_case("ExampleDownSRE")])
        self.assertEqual(covered, set())
        self.assertEqual(errors, [])

    def test_every_rule_of_an_alert_name_must_fire(self):
        self.write(RULE_FILE, two_rule_doc())
        self.rule_files = cpt.find_rule_files("deploy")
        covered, errors = self.coverage([firing_case("ExampleDownSRE")])
        self.assertEqual(covered, set())
        self.assertIn('"severity": "critical"', errors[0])

    def test_alert_name_with_two_rules_is_covered_when_both_fire(self):
        self.write(RULE_FILE, two_rule_doc())
        self.rule_files = cpt.find_rule_files("deploy")
        case = firing_case("ExampleDownSRE")
        case["exp_alerts"].append({"exp_labels": {"severity": "critical", "namespace": "openshift-monitoring"}})
        covered, errors = self.coverage([case])
        self.assertEqual(covered, {"ExampleDownSRE"})
        self.assertEqual(errors, [])

    def test_template_labels_are_ignored_when_matching(self):
        doc = copy.deepcopy(RULE_DOC)
        doc["spec"]["groups"][0]["rules"][1]["labels"]["namespace"] = "{{ $labels.namespace }}"
        self.write(RULE_FILE, doc)
        self.rule_files = cpt.find_rule_files("deploy")
        case = firing_case("ExampleDownSRE")
        case["exp_alerts"][0]["exp_labels"]["namespace"] = "openshift-example"
        covered, errors = self.coverage([case])
        self.assertEqual(covered, {"ExampleDownSRE"})
        self.assertEqual(errors, [])

    def test_unknown_alert_name_is_an_error(self):
        covered, errors = self.coverage([firing_case("ExampleTypoSRE")])
        self.assertEqual(covered, set())
        self.assertIn("does not define it", errors[0])


class CheckCoverageTests(RepoTestCase):
    def setUp(self):
        super().setUp()
        self.write(RULE_FILE, RULE_DOC)
        self.rule_files = cpt.find_rule_files("deploy")
        self.fp_down = cpt.fingerprint(self.rule_files[RULE_FILE].alerts["ExampleDownSRE"])
        self.fp_slow = cpt.fingerprint(self.rule_files[RULE_FILE].alerts["ExampleSlowSRE"])

    def test_all_covered_or_excepted_passes(self):
        problems = cpt.check_coverage(
            self.rule_files,
            {RULE_FILE: {"ExampleDownSRE"}},
            {RULE_FILE: {"ExampleSlowSRE": self.fp_slow}},
        )
        self.assertEqual(problems, {"untested": [], "changed": [], "stale": [], "removed": []})

    def test_untested_alert_fails(self):
        problems = cpt.check_coverage(self.rule_files, {RULE_FILE: {"ExampleDownSRE"}}, {})
        self.assertEqual(problems["untested"], [(RULE_FILE, "ExampleSlowSRE")])

    def test_changed_excepted_alert_fails(self):
        problems = cpt.check_coverage(
            self.rule_files,
            {RULE_FILE: {"ExampleDownSRE"}},
            {RULE_FILE: {"ExampleSlowSRE": "000000000000"}},
        )
        self.assertEqual(
            problems["changed"], [(RULE_FILE, "ExampleSlowSRE", "000000000000", self.fp_slow)]
        )

    def test_tested_alert_left_in_exceptions_fails(self):
        problems = cpt.check_coverage(
            self.rule_files,
            {RULE_FILE: {"ExampleDownSRE", "ExampleSlowSRE"}},
            {RULE_FILE: {"ExampleSlowSRE": self.fp_slow}},
        )
        self.assertEqual(problems["stale"], [(RULE_FILE, "ExampleSlowSRE")])

    def test_exception_for_deleted_alert_fails(self):
        problems = cpt.check_coverage(
            self.rule_files,
            {RULE_FILE: {"ExampleDownSRE", "ExampleSlowSRE"}},
            {"deploy/gone.yaml": {"GoneSRE": "abc"}, RULE_FILE: {"OldNameSRE": "abc"}},
        )
        self.assertEqual(
            problems["removed"], [("deploy/gone.yaml", "GoneSRE"), (RULE_FILE, "OldNameSRE")]
        )


class ExceptionsFileTests(RepoTestCase):
    def test_build_write_and_load_round_trip(self):
        self.write(RULE_FILE, RULE_DOC)
        rule_files = cpt.find_rule_files("deploy")
        exceptions = cpt.build_exceptions(rule_files, {RULE_FILE: {"ExampleDownSRE"}})
        self.assertEqual(list(exceptions[RULE_FILE]), ["ExampleSlowSRE"])
        path = "tests/prometheusrules/exceptions.yaml"
        cpt.write_exceptions(path, exceptions)
        self.assertEqual(cpt.load_exceptions(path), exceptions)
        with open(path) as f:
            self.assertTrue(f.read().startswith("# Alerts that do not have a unit test yet."))

    def test_octal_looking_fingerprint_round_trips(self):
        path = "tests/prometheusrules/exceptions.yaml"
        exceptions = {RULE_FILE: {"ExampleSlowSRE": "012345670123"}}
        cpt.write_exceptions(path, exceptions)
        self.assertEqual(cpt.load_exceptions(path), exceptions)

    def test_yaml_keyword_alert_name_round_trips(self):
        path = "tests/prometheusrules/exceptions.yaml"
        exceptions = {RULE_FILE: {"null": "52dd8cab9a08", "yes": "52dd8cab9a09"}}
        cpt.write_exceptions(path, exceptions)
        self.assertEqual(cpt.load_exceptions(path), exceptions)

    def test_missing_file_is_empty(self):
        self.assertEqual(cpt.load_exceptions("tests/prometheusrules/exceptions.yaml"), {})


class PreparePromtoolInputTests(RepoTestCase):
    def test_rewrites_rule_files_to_extracted_spec(self):
        self.write(RULE_FILE, RULE_DOC)
        self.write(TEST_FILE, test_doc([firing_case("ExampleDownSRE")]))
        rule_files = cpt.find_rule_files("deploy")
        parsed = cpt.parse_test_file(TEST_FILE, rule_files)
        with tempfile.TemporaryDirectory() as workdir:
            first = cpt.prepare_promtool_input(parsed, rule_files, workdir)
            second = cpt.prepare_promtool_input(parsed, rule_files, workdir)
            self.assertNotEqual(first, second)
            with open(first) as f:
                rewritten = yaml.safe_load(f)
            self.assertEqual(len(rewritten["rule_files"]), 1)
            with open(rewritten["rule_files"][0]) as f:
                self.assertEqual(json.load(f), RULE_DOC["spec"])
            self.assertEqual(rewritten["tests"], parsed.doc["tests"])


class FormatReportTests(unittest.TestCase):
    def test_empty_when_no_problems(self):
        self.assertEqual(
            cpt.format_report({"untested": [], "changed": [], "stale": [], "removed": []}), ""
        )

    def test_explains_what_to_do(self):
        report = cpt.format_report(
            {
                "untested": [(RULE_FILE, "NewSRE")],
                "changed": [(RULE_FILE, "OldSRE", "a", "b")],
                "stale": [(RULE_FILE, "DoneSRE")],
                "removed": [(RULE_FILE, "GoneSRE")],
            }
        )
        self.assertIn("Alerts without a unit test (1):", report)
        self.assertIn("Add a test case where this alert fires to '%s'." % TEST_FILE, report)
        self.assertIn("You changed the expr, for, keep_firing_for or labels", report)
        self.assertIn("Alerts that have a test but are still in the exception list (1):", report)
        self.assertIn("Alerts in the exception list that no longer exist (1):", report)


class MainTests(RepoTestCase):
    def setUp(self):
        super().setUp()
        self.write(RULE_FILE, RULE_DOC)
        self.write(TEST_FILE, test_doc([silent_case("ExampleDownSRE"), firing_case("ExampleDownSRE")]))

    def run_main(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = cpt.main(list(argv))
        return code, out.getvalue()

    def fake_promtool(self, exit_code, message):
        path = Path(self._tmp.name, "fake-promtool")
        path.write_text(
            textwrap.dedent(
                """\
                #!/bin/sh
                echo "%s"
                exit %d
                """
            )
            % (message, exit_code)
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)
        return str(path)

    def test_fails_when_alert_has_no_test(self):
        code, out = self.run_main("--skip-promtool")
        self.assertEqual(code, 1)
        self.assertIn("'ExampleSlowSRE' in '%s'" % RULE_FILE, out)
        self.assertIn(cpt.DOCS_FILE, out)

    def test_update_exceptions_then_pass(self):
        code, out = self.run_main("--update-exceptions")
        self.assertEqual(code, 0, out)
        code, out = self.run_main("--skip-promtool")
        self.assertEqual(code, 0, out)
        self.assertIn("1 of 2 alerts tested", out)

    def test_reports_promtool_failure(self):
        self.run_main("--update-exceptions")
        promtool = self.fake_promtool(1, "FAILED: alertname: ExampleDownSRE")
        code, out = self.run_main("--promtool", promtool)
        self.assertEqual(code, 1)
        self.assertIn("promtool test failed: '%s'" % TEST_FILE, out)
        self.assertIn("FAILED: alertname: ExampleDownSRE", out)

    def test_passes_when_promtool_passes(self):
        self.run_main("--update-exceptions")
        promtool = self.fake_promtool(0, "SUCCESS")
        code, out = self.run_main("--promtool", promtool)
        self.assertEqual(code, 0, out)
        self.assertIn("Running 1 test files with promtool:", out)
        self.assertIn("  ok   %s (" % TEST_FILE, out)

    def test_progress_marks_failed_file(self):
        self.run_main("--update-exceptions")
        promtool = self.fake_promtool(1, "FAILED")
        code, out = self.run_main("--promtool", promtool)
        self.assertEqual(code, 1)
        self.assertIn("  FAIL %s (" % TEST_FILE, out)

    def test_missing_promtool_is_reported(self):
        self.run_main("--update-exceptions")
        code, out = self.run_main("--promtool", "/does/not/exist/promtool")
        self.assertEqual(code, 1)
        self.assertIn("cannot find promtool", out)


if __name__ == "__main__":
    unittest.main()
