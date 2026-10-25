import sys
import tempfile
import unittest
from pathlib import Path

from scripts.db_targets import Target, resolve_target
from scripts.dev_test_target import DevTestTargetError, inspect_suite
from scripts.local_config import ConfigError, read_project_env
from scripts.migration_checks import _render_check_driver
from scripts.new_migration import owner_check
from scripts.schema_catalog import CatalogError, parse_inventory


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
try:
    from test_schema_catalog import fixture_payload, framed
finally:
    sys.path.pop(0)

BASE = {
    "CODE_SQLCL_CONNECTION": "dev-db",
    "CODE_EXPECTED_USER": "APP_DEV",
    "CODE_SCHEMA": "APP_DEV",
    "DB_ENVIRONMENT": "development",
    "STAGING_SQLCL_CONNECTION": "stage-db",
    "STAGING_EXPECTED_USER": "APP_LOGIN",
    "STAGING_SCHEMA": "APP_STAGE",
}


class LoginDiffersFromSchemaTests(unittest.TestCase):
    def test_target_keeps_login_and_schema_apart(self) -> None:
        target = resolve_target(BASE, "staging", "migration")

        self.assertEqual((target.expected_user, target.schema), ("APP_LOGIN", "APP_STAGE"))

    def test_multi_schema_lists_stay_position_aligned(self) -> None:
        values = {
            **BASE,
            "STAGING_SQLCL_CONNECTION": "stage-a,stage-b",
            "STAGING_EXPECTED_USER": "APP_LOGIN,APP_LOGIN",
            "STAGING_SCHEMA": "APP_STAGE,APP_DEV",
        }

        target = resolve_target(values, "staging", "migration", schema="APP_DEV")

        self.assertEqual((target.connection, target.expected_user, target.schema), ("stage-b", "APP_LOGIN", "APP_DEV"))

    def test_migration_guard_checks_login_before_switching_schema(self) -> None:
        contents = (ROOT / "scripts" / "verify_migration_access.sql").read_text(encoding="utf-8")

        session_user_check = contents.index("IF l_session_user != c_expected_user")
        schema_switch = contents.index("ALTER SESSION SET CURRENT_SCHEMA =")
        current_schema_check = contents.index("IF SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') != c_target_schema")
        self.assertLess(session_user_check, schema_switch)
        self.assertLess(schema_switch, current_schema_check)

    def test_publish_guard_compares_both_identities(self) -> None:
        contents = (ROOT / "scripts" / "publish_identity_guard.sql").read_text(encoding="utf-8")

        self.assertIn("require_equal('SESSION_USER'", contents)
        self.assertIn("require_equal('CURRENT_SCHEMA'", contents)

    def test_generated_owner_check_reads_current_schema_not_session_user(self) -> None:
        sql = owner_check("APP_STAGE")["sql"]

        self.assertIn("CURRENT_SCHEMA", sql)
        self.assertNotIn("SESSION_USER", sql)

    def test_check_driver_switches_schema_and_reports_both_identities(self) -> None:
        target = Target("staging", "stage-db", "APP_LOGIN", "APP_STAGE", "staging")
        driver = _render_check_driver(target, [], "preconditions")

        schema_switch = driver.index("ALTER SESSION SET CURRENT_SCHEMA = APP_STAGE;")
        declaration = driver.index("DECLARE")
        self.assertLess(schema_switch, declaration)
        self.assertIn("l_result.put('session_user'", driver)
        self.assertIn("l_result.put('current_schema'", driver)

    def test_catalog_accepts_metadata_privilege_path_for_non_owner(self) -> None:
        target = Target("staging", "stage-db", "APP_LOGIN", "APP_STAGE", "staging")

        permitted = fixture_payload("owner-inventory.json")
        permitted["identity"].update({"session_user": "APP_LOGIN", "current_schema": "APP_STAGE"})
        for item in permitted["objects"]:
            item["owner"] = "APP_STAGE"
        permitted["coverage"].update({
            "path": "METADATA_PRIVILEGE",
            "privileges": ["SELECT ANY DICTIONARY"],
            "metadataReadable": True,
        })
        inventory = parse_inventory(framed(permitted), target)
        self.assertTrue(inventory.coverage["ownerComplete"])

        denied = fixture_payload("owner-inventory.json")
        denied["identity"].update({"session_user": "APP_LOGIN", "current_schema": "APP_STAGE"})
        for item in denied["objects"]:
            item["owner"] = "APP_STAGE"
        denied["coverage"].update({"path": "METADATA_PRIVILEGE", "privileges": [], "metadataReadable": True})
        with self.assertRaisesRegex(CatalogError, "enabled metadata-reader privileges were not validated"):
            parse_inventory(framed(denied), target)

    def test_owner_only_commands_name_the_reason(self) -> None:
        dev_values = {
            "CODE_SQLCL_CONNECTION": "dev-db",
            "CODE_EXPECTED_USER": "APP_LOGIN",
            "CODE_SCHEMA": "APP_STAGE",
            "DB_ENVIRONMENT": "development",
        }
        with self.assertRaises(DevTestTargetError) as dev_error:
            inspect_suite(dev_values, "APP_STAGE", None, None)
        self.assertIn("session_user", str(dev_error.exception))
        self.assertIn("selected_schema", str(dev_error.exception))

        env_text = "\n".join((
            "PROJECT_NAME=APP_LOGIN",
            "DEVELOPER_NAME=APP_DEV",
            "DB_ENVIRONMENT=development",
            "APEX_APP_ID=100",
            "TABLES_SCHEMA=APP_DEV",
            "TABLES_PREFIXES=*",
            "TABLES_SQLCL_CONNECTION=dev-db",
            "TABLES_EXPECTED_USER=APP_DEV",
            "CODE_SCHEMA=APP_DEV",
            "CODE_PREFIXES=*",
            "CODE_SQLCL_CONNECTION=dev-db",
            "CODE_EXPECTED_USER=APP_DEV",
            "APEX_PARSING_SCHEMA=APP_DEV",
            "APEX_SQLCL_CONNECTION=dev-db",
            "APEX_EXPECTED_USER=APP_DEV",
            "ORDS_SCHEMA=APP_STAGE",
            "ORDS_SQLCL_CONNECTION=stage-db",
            "ORDS_EXPECTED_USER=APP_LOGIN",
            "",
        ))
        with tempfile.TemporaryDirectory() as temporary:
            env_path = Path(temporary) / ".env"
            env_path.write_text(env_text, encoding="utf-8")
            with self.assertRaises(ConfigError) as config_error:
                read_project_env(env_path)
        self.assertIn("needs the schema owner", str(config_error.exception))


if __name__ == "__main__":
    unittest.main()
