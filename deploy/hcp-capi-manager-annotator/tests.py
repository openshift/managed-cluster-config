import unittest

from should_patch import action, needs_pin


class TestShouldPatch(unittest.TestCase):

    def test_419_is_pinned(self):
        self.assertTrue(needs_pin("4.19.0"))
        self.assertTrue(needs_pin("4.19.31"))

    def test_420_is_pinned(self):
        self.assertTrue(needs_pin("4.20.0"))
        self.assertTrue(needs_pin("4.20.7"))

    def test_421_is_not_pinned(self):
        self.assertFalse(needs_pin("4.21.0"))
        self.assertFalse(needs_pin("4.21.9"))

    def test_newer_versions_are_not_pinned(self):
        self.assertFalse(needs_pin("4.22.1"))
        self.assertFalse(needs_pin("5.0.0"))

    def test_prerelease_suffix_is_ignored(self):
        self.assertTrue(needs_pin("4.20.0-rc.1"))

    def test_unparsable_version_skips(self):
        self.assertEqual(action("not-a-version"), "skip")
        self.assertEqual(action(""), "skip")
        self.assertFalse(needs_pin("10"))

    def test_action_values(self):
        self.assertEqual(action("4.19.5"), "pin")
        self.assertEqual(action("4.21.5"), "remove")


if __name__ == "__main__":
    unittest.main()
