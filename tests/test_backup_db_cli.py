import os
import shutil
import subprocess
import _test_subprocess_safety  # noqa: F401
import tempfile
import unittest
from pathlib import Path
import _no_real_sqlcl  # noqa: F401  (keeps tests away from a real SQLcl)
import fake_sqlcl
from fake_sqlcl import BASH


ROOT = Path(__file__).resolve().parents[1]
PWSH = _test_subprocess_safety.working_pwsh()


class BackupDbCliTests(unittest.TestCase):
    def make_checkout(self, root: Path, powershell: bool) -> Path:
        scripts = root / "scripts"
        scripts.mkdir(parents=True)
        if powershell:
            names = (
                "backup_db.ps1",
                "backup_db.sql",
                "backup_manifest.py",
                "load_env.ps1",
                "check_db_target.ps1",
                "invoke_sqlcl.ps1", "resolve_python.ps1",
                "replace_mirror.ps1",
            )
        else:
            names = (
                "backup_db.sh",
                "backup_db.sql",
                "backup_manifest.py",
                "load_env.sh",
                "check_db_target.sh",
                "sqlcl_safe.sh",
                "replace_mirror.sh",
            )
        for name in names:
            shutil.copy2(ROOT / "scripts" / name, scripts / name)

        if powershell:
            ps_spy = scripts / "replace_mirror.ps1"
            content = ps_spy.read_text(encoding="utf-8")
            marker = '$ErrorActionPreference = "Stop"\n'
            idx = content.find(marker) + len(marker)
            spy_code = "[System.IO.File]::WriteAllText((Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path '.replace_mirror_called'), 'called')\n"
            ps_spy.write_text(content[:idx] + spy_code + content[idx:], encoding="utf-8")
        else:
            sh_spy = scripts / "replace_mirror.sh"
            content = sh_spy.read_text(encoding="utf-8")
            sh_spy.write_text("#!/usr/bin/env bash\ntouch \"$(cd \"$(dirname \"$0\")/..\" && pwd -P)/.replace_mirror_called\"\n" + content[content.find("\n") + 1:], encoding="utf-8")

        env_text = (ROOT / ".env.example").read_text(encoding="utf-8")
        env_text = env_text.replace("TABLES_SCHEMA=DEMO", "TABLES_SCHEMA=DEMO$")
        env_text = env_text.replace("CODE_SCHEMA=DEMO", "CODE_SCHEMA=DEMO$")
        (root / ".env").write_text(env_text, encoding="utf-8")

        (root / "README.md").write_text("seed\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        subprocess.run(["git", "-C", str(root), "config", "user.name", "Backup Test"], check=True)
        subprocess.run(["git", "-C", str(root), "config", "user.email", "backup@example.test"], check=True)
        subprocess.run(["git", "-C", str(root), "add", "README.md"], check=True)
        subprocess.run(["git", "-C", str(root), "commit", "-qm", "seed"], check=True)

        fake_bin = root / "bin"
        fake_bin.mkdir()
        fake_sql = fake_bin / "sql"
        fake_sql.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "cat > /dev/null\n"
            "# SQLcl prints this advisory for backup_db.sql's large LONG setting.\n"
            "printf '%s\\n' 'Warning: This LONG setting may cause Java memory problems.' 'It is recommended to reduce the setting and/or increase the memory available to Java.' 'FAKE SQLCL PROGRESS LINE'\n"
            "schema=\"$6\"\n"
            "scope=\"$7\"\n"
            "spool_schema=\"${11:-}\"\n"
            "if [[ -z \"$spool_schema\" || \"$spool_schema\" == *'$'* ]]; then\n"
            "  printf '%s\\n' 'SP2-0332: Cannot create spool file'\n"
            "  exit 0\n"
            "fi\n"
            "case \"$scope\" in\n"
            "  tables) scope_dir=tables; object=FAKE_TABLE ;;\n"
            "  code) scope_dir=views; object=FAKE_VIEW ;;\n"
            "  *) exit 4 ;;\n"
            "esac\n"
            "mkdir -p \"database/$spool_schema/$scope_dir\"\n"
            "printf 'CREATE FAKE OBJECT;\\n' > \"database/$spool_schema/$scope_dir/$object.sql\"\n"
            "# Mirrors the real driver's complete, alphabetically ordered type rows.\n"
            "if [[ -n \"${FAKE_MANIFEST_CODE:-}\" && \"$scope\" == code ]]; then\n"
            "  printf '%s' \"$FAKE_MANIFEST_CODE\" > \"database/$spool_schema/manifest-$scope.txt\"\n"
            "elif [[ -n \"${FAKE_MANIFEST_TABLES:-}\" && \"$scope\" == tables ]]; then\n"
            "  printf '%s' \"$FAKE_MANIFEST_TABLES\" > \"database/$spool_schema/manifest-$scope.txt\"\n"
            "elif [[ \"$scope\" == tables ]]; then\n"
            "  printf 'TABLE=1\\n' > \"database/$spool_schema/manifest-$scope.txt\"\n"
            "else\n"
            "  printf 'FUNCTION=0\\nPACKAGE=0\\nPACKAGE BODY=0\\nPROCEDURE=0\\nSYNONYM=0\\nTRIGGER=0\\nVIEW=1\\n' > \"database/$spool_schema/manifest-$scope.txt\"\n"
            "fi\n",
            encoding="utf-8",
        )
        fake_sql.chmod(0o755)
        fake_sqlcl.add_launcher(fake_bin)
        return scripts / ("backup_db.ps1" if powershell else "backup_db.sh")

    def run_backup(
        self, script: Path, powershell: bool, extra_env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["PATH"] = f"{script.parents[1] / 'bin'}{os.pathsep}{environment['PATH']}"
        environment["PROJECT_ENV_FILE"] = str(script.parents[1] / ".env")
        if extra_env:
            environment.update(extra_env)
        command = (
            [PWSH, "-NoProfile", "-File", str(script)]
            if powershell
            else [BASH, str(script)]
        )
        return subprocess.run(
            command,
            cwd=script.parents[1],
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_dollar_schema_mirror_installed(self, script: Path, output: str) -> None:
        mirror = script.parents[1] / "database" / "DEMO$"
        self.assertTrue(mirror.is_dir(), output)
        self.assertEqual((mirror / "manifest-tables.txt").read_text(encoding="utf-8"), "TABLE=1\n")
        self.assertEqual(
            (mirror / "manifest-code.txt").read_text(encoding="utf-8"),
            "FUNCTION=0\nPACKAGE=0\nPACKAGE BODY=0\nPROCEDURE=0\nSYNONYM=0\nTRIGGER=0\nVIEW=1\n",
        )
        self.assertTrue((mirror / "tables" / "FAKE_TABLE.sql").is_file())
        self.assertTrue((mirror / "views" / "FAKE_VIEW.sql").is_file())
        # The LONG advisory is dropped; the rest of SQLcl's output is kept.
        self.assertNotIn("LONG setting may cause Java memory problems", output)
        self.assertNotIn("increase the memory available to Java", output)
        self.assertIn("FAKE SQLCL PROGRESS LINE", output)
        database_entries = [path.name for path in (script.parents[1] / "database").iterdir()]
        self.assertEqual(database_entries, ["DEMO$"])

    def seed_old_mirror(self, root: Path) -> tuple[Path, str]:
        old_mirror_dir = root / "database" / "DEMO$" / "tables"
        old_mirror_dir.mkdir(parents=True)
        old_file = old_mirror_dir / "OLD_TABLE.sql"
        old_content = "CREATE TABLE OLD_TABLE (ID NUMBER);\n"
        old_file.write_text(old_content, encoding="utf-8")
        (root / "database" / "DEMO$" / "manifest-tables.txt").write_text("TABLE=1\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "database"], check=True)
        subprocess.run(["git", "-C", str(root), "commit", "-qm", "seed old mirror"], check=True)
        return old_file, old_content

    def assert_malformed_manifest_refused_and_old_mirror_preserved(self, powershell: bool) -> None:
        malformed_cases = [
            ("negative_count", "FUNCTION=0\nPACKAGE=0\nPACKAGE BODY=0\nPROCEDURE=0\nSYNONYM=0\nTRIGGER=-1\nVIEW=1\n"),
            ("duplicate_row", "FUNCTION=0\nPACKAGE=0\nPACKAGE BODY=0\nPROCEDURE=0\nSYNONYM=0\nTRIGGER=0\nVIEW=1\nTRIGGER=0\n"),
            ("unknown_type", "FUNCTION=0\nPACKAGE=0\nPACKAGE BODY=0\nPROCEDURE=0\nSYNONYM=0\nTRIGGER=0\nVIEW=1\nUNKNOWN=0\n"),
            ("missing_row", "FUNCTION=0\nPACKAGE=0\nPACKAGE BODY=0\nPROCEDURE=0\nSYNONYM=0\nVIEW=1\n"),
            ("count_mismatch", "FUNCTION=0\nPACKAGE=0\nPACKAGE BODY=0\nPROCEDURE=0\nSYNONYM=0\nTRIGGER=0\nVIEW=2\n"),
            ("non_ascii_separator", "FUNCTION=0\nPACKAGE=0\nPACKAGE BODY=0\nPROCEDURE=0\nSYNONYM=0\nTRIGGER=0\nVIEW=1\u0085\n"),
        ]
        for name, manifest_code in malformed_cases:
            with self.subTest(case=name):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    script = self.make_checkout(root, powershell=powershell)
                    old_file, old_content = self.seed_old_mirror(root)

                    result = self.run_backup(script, powershell=powershell, extra_env={"FAKE_MANIFEST_CODE": manifest_code})

                    self.assertEqual(result.returncode, 2, f"Failed on {name}: {result.stdout}\n{result.stderr}")
                    self.assertFalse((root / ".replace_mirror_called").exists(), f"replace_mirror was invoked on {name}")
                    self.assertEqual(old_file.read_text(encoding="utf-8"), old_content, f"Old mirror was overwritten on {name}")
                    self.assertFalse((root / "database" / "DEMO$" / "views").exists(), f"New views directory was installed on {name}")

    def assert_valid_manifest_installed(self, powershell: bool) -> None:
        valid_code = "\v\f\r\n" + "".join(
            f"\v{kind}\f=\v{count}\f\r\n"
            for kind, count in (("FUNCTION", 0), ("PACKAGE", 0), ("PACKAGE BODY", 0),
                                ("PROCEDURE", 0), ("SYNONYM", 0), ("TRIGGER", 0), ("VIEW", 1))
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = self.make_checkout(root, powershell=powershell)
            result = self.run_backup(script, powershell=powershell, extra_env={"FAKE_MANIFEST_CODE": valid_code})

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((root / ".replace_mirror_called").exists())
            self.assertTrue((root / "database" / "DEMO$" / "views" / "FAKE_VIEW.sql").is_file())

    def test_bash_backup_refuses_malformed_manifest_and_preserves_old_mirror(self) -> None:
        self.assert_malformed_manifest_refused_and_old_mirror_preserved(powershell=False)

    @unittest.skipUnless(PWSH, "PowerShell Core is not installed")
    def test_powershell_backup_refuses_malformed_manifest_and_preserves_old_mirror(self) -> None:
        self.assert_malformed_manifest_refused_and_old_mirror_preserved(powershell=True)

    def test_bash_backup_accepts_valid_crlf_and_whitespace_manifest(self) -> None:
        self.assert_valid_manifest_installed(powershell=False)

    @unittest.skipUnless(PWSH, "PowerShell Core is not installed")
    def test_powershell_backup_accepts_valid_crlf_and_whitespace_manifest(self) -> None:
        self.assert_valid_manifest_installed(powershell=True)

    def test_bash_backup_spools_safely_then_installs_original_dollar_schema_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            script = self.make_checkout(Path(temporary), powershell=False)

            result = self.run_backup(script, powershell=False)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_dollar_schema_mirror_installed(script, result.stdout + result.stderr)

    @unittest.skipUnless(PWSH, "PowerShell Core is not installed")
    def test_powershell_backup_spools_safely_then_installs_original_dollar_schema_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            script = self.make_checkout(Path(temporary), powershell=True)

            result = self.run_backup(script, powershell=True)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_dollar_schema_mirror_installed(script, result.stdout + result.stderr)

    def test_sql_driver_uses_wrapper_supplied_safe_schema_directory(self) -> None:
        script = (ROOT / "scripts" / "backup_db.sql").read_text(encoding="utf-8")
        self.assertIn("DEFINE spool_schema = '&6'", script)
        self.assertIn("SPOOL database/&&spool_schema/", script)
        self.assertNotIn("SPOOL database/&&target_schema/", script)


    def test_sql_driver_mirrors_private_synonyms_and_counts_them(self) -> None:
        script = (ROOT / "scripts" / "backup_db.sql").read_text(encoding="utf-8")
        self.assertIn("SPOOL database/&&spool_schema/synonyms/", script)
        self.assertIn("GET_DDL(''SYNONYM''", script)
        self.assertIn("SELECT 'SYNONYM', 'code' FROM dual", script)
        self.assertIn("'VIEW', 'PACKAGE', 'PACKAGE BODY', 'PROCEDURE', 'FUNCTION', 'TRIGGER', 'SYNONYM'", script)
        # Only the schema's own (private) synonyms: filtered by owner, never PUBLIC.
        self.assertIn(
            "AND objects_to_export.owner = UPPER('&&target_schema')\n  AND objects_to_export.object_type = 'SYNONYM'",
            script,
        )

if __name__ == "__main__":
    unittest.main()
