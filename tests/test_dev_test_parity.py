"""Pin the shared DEV-test contract without changing the 26.1 release identity."""
from __future__ import annotations

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_IDS = (
    "datatype-roundtrip",
    "compiler-settings",
    "sqlcl-delivery",
    "migration-success",
    "migration-refusal",
    "invalid-view",
)


class DevTestParityTests(unittest.TestCase):
    def test_26_1_manifest_identity_stays_release_specific(self) -> None:
        manifest = json.loads((ROOT / "template-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(1, manifest["schemaVersion"])
        self.assertEqual(
            "https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_26_1.git",
            manifest["upstream"],
        )
        self.assertNotIn("apexRelease", manifest)
        self.assertNotIn("minimumSqlclVersion", manifest)
        self.assertIn("docs/apex-26.1-qualification.md", manifest["templateOnly"])
        self.assertIn("docs/superpowers/**", manifest["templateOnly"])

    def test_builtin_scenario_ids_match_the_shared_contract(self) -> None:
        from scripts.dev_test_core import builtin_suite

        self.assertEqual(EXPECTED_IDS, tuple(item.id for item in builtin_suite().scenarios))

    def test_cli_options_and_report_schema_match_the_shared_contract(self) -> None:
        from scripts.dev_test import build_parser
        from scripts.dev_test_report import new_report, validate_report

        args = build_parser().parse_args(["--env", "dev", "--schema", "APP", "--run"])
        self.assertTrue(args.run)
        self.assertEqual("dev", args.env)
        self.assertEqual("APP", args.schema)

        report = validate_report(new_report(None, "plan", "builtin", list(EXPECTED_IDS), "builtin"))
        self.assertEqual(1, report["schemaVersion"])
        self.assertEqual(list(EXPECTED_IDS), report["selection"]["scenarioIds"])
        self.assertEqual(
            {
                "schemaVersion", "runId", "action", "startedAt", "finishedAt",
                "source", "selection", "target", "prerequisites", "scenarios",
                "inventory", "cleanup", "diagnostics", "limitations", "coverage",
            },
            set(report),
        )


if __name__ == "__main__":
    unittest.main()
