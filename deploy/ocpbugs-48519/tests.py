import unittest

from should_patch import should_patch

class TestShouldPatch(unittest.TestCase):

    def test_version_greater_than_compare_version(self):
        # Test where z stream version is greater than compare_version
        result = should_patch("4.15.15", "10")
        self.assertFalse(result)  # No patch needed, should return False

    def test_version_equal_to_compare_version(self):
        # Test where z stream version is equal to compare_version
        result = should_patch("4.15.10", "10")
        self.assertFalse(result)  # No patch needed, should return False

    def test_version_less_than_compare_version(self):
        # Test where z stream version is less than compare_version
        result = should_patch("4.15.5", "10")
        self.assertTrue(result)  # Patch needed, should return True

    def test_version_is_zero(self):
        # Test where z stream version is zero
        result = should_patch("4.15.0", "5")
        self.assertTrue(result)  # Patch needed, should return True

    def test_non_integer_version(self):
        # Test where parsing version fails, assert we default to patching
        result = should_patch("10.5.y", "10")
        self.assertTrue(result)

    def test_non_integer_compare_version(self):
        # Test where parsing compare_version fails, assert we default to patching
        result = should_patch("10", "10.5y")
        self.assertTrue(result)

if __name__ == '__main__':
    unittest.main()
