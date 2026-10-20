"""`team.sh verify-local` and `team.ps1 verify-local` reach scripts/verify_local.py before any .env is loaded."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import _no_real_sqlcl  # noqa: F401  (keeps tests away from a real SQLcl)
from fake_sqlcl import BASH

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")


def launchers():
    yield "team.sh", [BASH]
    if PWSH:
        yield "team.ps1", [PWSH, "-NoProfile", "-File"]


class VerifyLocalCliTests(unittest.TestCase):
    def test_a_broken_env_is_reported_as_a_failed_check_without_leaking_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / "repo"
            (repo / "apps").mkdir(parents=True)
            (repo / "template-manifest.json").write_text(json.dumps({
                "schemaVersion": 1, "upstream": "https://example.com/template.git",
                "templateOwned": [], "projectOwned": [], "templateOnly": [],
            }), encoding="utf-8")
            secret = "SUPER_SECRET_TOKEN_9999"
            (repo / ".env").write_text(f"INVALID_LINE {secret}\n", encoding="utf-8")
            for entry, launcher in launchers():
                with self.subTest(entry=entry):
                    result = subprocess.run(
                        [*launcher, str(ROOT / "scripts" / entry), "verify-local", "--repo-root", str(repo), "--format", "json"],
                        capture_output=True, text=True, check=False)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertNotIn(secret, result.stdout + result.stderr)
                    data = json.loads(result.stdout)
                    self.assertEqual((data["schemaVersion"], data["exitCode"]), (1, 2))

    def test_runs_from_another_directory_with_a_clean_pythonpath(self) -> None:
        clean = {key: value for key, value in os.environ.items() if key != "PYTHONPATH"}
        with tempfile.TemporaryDirectory() as temporary:
            for entry, launcher in launchers():
                with self.subTest(entry=entry):
                    result = subprocess.run(
                        [*launcher, str(ROOT / "scripts" / entry), "verify-local", "--format", "json"],
                        cwd=temporary, env=clean, capture_output=True, text=True, check=False)
                    self.assertNotIn("ModuleNotFoundError", result.stderr)
                    self.assertEqual(json.loads(result.stdout)["schemaVersion"], 1)

    def test_help_lists_verify_local_and_it_takes_no_schema(self) -> None:
        for entry, launcher in launchers():
            with self.subTest(entry=entry):
                help_text = subprocess.run([*launcher, str(ROOT / "scripts" / entry), "--help"],
                                           capture_output=True, text=True, check=False, cwd=ROOT).stdout
                self.assertIn("verify-local [--format text|json] [--live]", help_text)
                self.assertIn("except upgrade-template, verify-local,", help_text)


if __name__ == "__main__":
    unittest.main()
