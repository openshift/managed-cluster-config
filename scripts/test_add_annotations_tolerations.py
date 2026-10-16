#!/usr/bin/env python3
"""Unit tests for add-annotations-tolerations.py post-processing.

Run: python3 -m unittest scripts/test_add_annotations_tolerations.py
Uses oyaml if present (what the generation pipeline uses); otherwise falls back
to PyYAML, so no extra install is required to run the test.
"""
import importlib.util
import os
import sys
import tempfile
import unittest

# oyaml is a thin ordered-dict wrapper around PyYAML. Prefer it, but fall back to
# PyYAML so this test runs in a bare environment. The shim also satisfies the
# module-under-test's own `import oyaml`.
try:
    import oyaml as yaml
except ModuleNotFoundError:
    import yaml
    sys.modules["oyaml"] = yaml

# Load the hyphenated module file by path. The script has a module-level
# PlacementBinding-rename block that globs deploy/acm-policies/ at import time,
# so import it from an empty temp CWD to keep the test free of side effects.
_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "add_annotations_tolerations",
    os.path.join(_HERE, "add-annotations-tolerations.py"),
)
mod = importlib.util.module_from_spec(_spec)
_cwd = os.getcwd()
with tempfile.TemporaryDirectory() as _d:
    os.chdir(_d)
    try:
        _spec.loader.exec_module(mod)
    finally:
        os.chdir(_cwd)


class AddAnnotationsTolerations(unittest.TestCase):
    def _run(self, docs):
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
            yaml.dump_all(docs, f, default_flow_style=False)
            path = f.name
        try:
            ok = mod.add_annotations_and_tolerations(path)
            with open(path) as fh:
                out = list(yaml.safe_load_all(fh))
        finally:
            os.unlink(path)
        return ok, out

    def test_policy_gets_empty_description_annotation(self):
        ok, out = self._run([{"apiVersion": "policy.open-cluster-management.io/v1",
                              "kind": "Policy",
                              "metadata": {"name": "p1"}}])
        self.assertTrue(ok)
        ann = out[0]["metadata"]["annotations"]
        self.assertIn(mod.POLICY_DESCRIPTION_ANNOTATION, ann)
        self.assertEqual(ann[mod.POLICY_DESCRIPTION_ANNOTATION], "")

    def test_placement_gets_tolerations(self):
        ok, out = self._run([{"apiVersion": "cluster.open-cluster-management.io/v1beta1",
                              "kind": "Placement",
                              "metadata": {"name": "pl1"},
                              "spec": {}}])
        self.assertTrue(ok)
        self.assertEqual(out[0]["spec"]["tolerations"], mod.PLACEMENT_TOLERATIONS)

    def test_existing_description_is_not_overwritten(self):
        ok, out = self._run([{"apiVersion": "policy.open-cluster-management.io/v1",
                              "kind": "Policy",
                              "metadata": {"name": "p2", "annotations": {
                                  mod.POLICY_DESCRIPTION_ANNOTATION: "keep me"}}}])
        self.assertTrue(ok)
        self.assertEqual(
            out[0]["metadata"]["annotations"][mod.POLICY_DESCRIPTION_ANNOTATION], "keep me")

    def test_existing_tolerations_are_not_overwritten(self):
        custom = [{"key": "x", "operator": "Exists"}]
        ok, out = self._run([{"apiVersion": "cluster.open-cluster-management.io/v1beta1",
                              "kind": "Placement", "metadata": {"name": "pl2"},
                              "spec": {"tolerations": custom}}])
        self.assertTrue(ok)
        self.assertEqual(out[0]["spec"]["tolerations"], custom)

    def test_other_kinds_untouched(self):
        ok, out = self._run([{"apiVersion": "v1", "kind": "ConfigMap",
                              "metadata": {"name": "cm"}}])
        self.assertTrue(ok)
        self.assertNotIn("annotations", out[0].get("metadata", {}))


if __name__ == "__main__":
    unittest.main()
