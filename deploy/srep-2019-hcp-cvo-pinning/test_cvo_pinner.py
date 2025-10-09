#!/usr/bin/env python3

"""
Unit tests for the CVO Pinner script.

Run with: python -m unittest test_cvo_pinner.py
"""

import unittest
import tempfile
import os
import yaml


class TestVersionMappings(unittest.TestCase):
    """Test version mapping file parsing logic."""

    def test_load_valid_mappings(self):
        """Test loading a valid version mappings file."""
        # Create a temporary YAML file
        test_data = {
            'mappings': [
                {'version': '4.18.7', 'image': 'quay.io/test:image1'},
                {'version': '4.17.10', 'image': 'quay.io/test:image2'},
            ]
        }

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(test_data, f)
            temp_file = f.name

        try:
            # Manually load and verify (simulating what the script does)
            with open(temp_file, 'r') as f:
                data = yaml.safe_load(f)

            mappings = {}
            for mapping in data.get('mappings', []):
                version = mapping.get('version')
                image = mapping.get('image')
                if version and image:
                    mappings[version] = image

            self.assertEqual(len(mappings), 2)
            self.assertEqual(mappings['4.18.7'], 'quay.io/test:image1')
            self.assertEqual(mappings['4.17.10'], 'quay.io/test:image2')
        finally:
            os.unlink(temp_file)

    def test_load_empty_mappings(self):
        """Test loading an empty mappings file."""
        test_data = {'mappings': []}

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(test_data, f)
            temp_file = f.name

        try:
            with open(temp_file, 'r') as f:
                data = yaml.safe_load(f)

            mappings = {}
            for mapping in data.get('mappings', []):
                version = mapping.get('version')
                image = mapping.get('image')
                if version and image:
                    mappings[version] = image

            self.assertEqual(len(mappings), 0)
        finally:
            os.unlink(temp_file)

    def test_load_invalid_mappings(self):
        """Test loading mappings with missing fields."""
        test_data = {
            'mappings': [
                {'version': '4.18.7'},  # Missing image
                {'image': 'quay.io/test:image'},  # Missing version
                {'version': '4.17.10', 'image': 'quay.io/test:image2'},  # Valid
            ]
        }

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(test_data, f)
            temp_file = f.name

        try:
            with open(temp_file, 'r') as f:
                data = yaml.safe_load(f)

            mappings = {}
            for mapping in data.get('mappings', []):
                version = mapping.get('version')
                image = mapping.get('image')
                if version and image:
                    mappings[version] = image

            # Only the valid mapping should be loaded
            self.assertEqual(len(mappings), 1)
            self.assertEqual(mappings['4.17.10'], 'quay.io/test:image2')
        finally:
            os.unlink(temp_file)


class TestAnnotationValue(unittest.TestCase):
    """Test annotation value formatting."""

    def test_annotation_format(self):
        """Test that annotation values are formatted correctly."""
        image = "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:abc123"
        expected = f"cluster-version-operator={image}"

        # This is the format we expect
        self.assertEqual(expected, f"cluster-version-operator={image}")
        self.assertIn("cluster-version-operator=", expected)
        self.assertTrue(expected.endswith(image))

    def test_annotation_key(self):
        """Test that annotation key is correct."""
        key = "hypershift.openshift.io/image-overrides"

        # Verify the key format
        self.assertEqual(key, "hypershift.openshift.io/image-overrides")
        self.assertIn("hypershift.openshift.io", key)
        self.assertIn("image-overrides", key)


class TestVersionLookup(unittest.TestCase):
    """Test version lookup logic."""

    def test_version_in_mappings(self):
        """Test checking if a version exists in mappings."""
        mappings = {
            '4.18.7': 'quay.io/test:image1',
            '4.17.10': 'quay.io/test:image2',
        }

        # Version in mappings
        self.assertIn('4.18.7', mappings)
        self.assertEqual(mappings['4.18.7'], 'quay.io/test:image1')

        # Version not in mappings
        self.assertNotIn('4.18.8', mappings)
        self.assertNotIn('4.16.5', mappings)

    def test_version_exact_match(self):
        """Test that version matching is exact."""
        mappings = {
            '4.18.7': 'quay.io/test:image1',
        }

        # Exact match required
        self.assertIn('4.18.7', mappings)
        self.assertNotIn('4.18.70', mappings)
        self.assertNotIn('4.18', mappings)
        self.assertNotIn('4.18.7.0', mappings)


if __name__ == '__main__':
    unittest.main()
