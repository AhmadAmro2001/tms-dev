import json
import tempfile
import unittest
from pathlib import Path

from scripts.deployment_descriptor import DescriptorError, read_descriptor


def descriptor():
    return {
        "workspace": {"name": "TEAM"},
        "app": {"id": 100, "databaseSession": {"parsingSchema": "APP"}},
    }


class DeploymentDescriptorTests(unittest.TestCase):
    def test_reads_the_explicit_apex_26_1_descriptor_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "staging.json"
            expected = descriptor()
            path.write_text(json.dumps(expected), encoding="utf-8")
            self.assertEqual(read_descriptor(path, 100), expected)

    def test_rejects_missing_identity_mismatch_and_unknown_properties(self):
        for value in (
            {},
            {"workspace": {"name": "TEAM"}},
            {"workspace": {"name": "TEAM"}, "app": {"id": 101, "databaseSession": {"parsingSchema": "APP"}}},
            {**descriptor(), "app": {**descriptor()["app"], "runtime": {"debugging": True}}},
        ):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "descriptor.json"
                path.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaises(DescriptorError):
                    read_descriptor(path, 100)

    def test_rejects_non_utf8_bom_duplicate_and_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "descriptor.json"
            for raw in (
                b"\xef\xbb\xbf" + json.dumps(descriptor()).encode("utf-8"),
                b'{"workspace":{"name":"A","name":"B"},"app":{}}',
                b'{"workspace":{"name":NaN},"app":{}}',
            ):
                path.write_bytes(raw)
                with self.subTest(raw=raw), self.assertRaises(DescriptorError):
                    read_descriptor(path, 100)


if __name__ == "__main__":
    unittest.main()
