"""Recorded-catalog and fake-SQLcl coverage for compare-env."""

from __future__ import annotations

import base64
import gzip
import io
import json
import os
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr, redirect_stdout
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

import _no_real_sqlcl  # noqa: F401
from tests import fake_sqlcl
from scripts import compare_schema, migration_runtime
from scripts.db_targets import Target
from scripts.compare_schema import (
    COMPARE_ENV_SECTIONS,
    _environment_driver,
    capture_environment_catalog,
    compare_environment_catalogs,
    emit_dba_script,
    parse_environment_catalog_output,
    render_environment_report,
)
from scripts.schema_catalog import CatalogError


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures" / "compare_env"


def catalog(name: str) -> dict:
    return json.loads((FIXTURES / f"{name}.json").read_text(encoding="utf-8"))


def framed(payload: dict) -> str:
    encoded = base64.b64encode(gzip.compress(json.dumps(payload, separators=(",", ":")).encode("utf-8"))).decode("ascii")
    chunks = [encoded[index:index + 120] for index in range(0, len(encoded), 120)]
    return "\n".join((
        "CATALOG_PAYLOAD_BEGIN:compare-env",
        "CATALOG_ENCODING:gzip-base64-v1",
        *chunks,
        "CATALOG_PAYLOAD_END:compare-env",
        "CATALOG_VERIFIED:compare-env",
    ))


def _without_sql_literals(source: str) -> str:
    """Remove standard and Oracle alternative-quoted SQL literals."""
    result = []
    index = 0
    while index < len(source):
        if source[index:index + 2].lower() == "q'" and index + 2 < len(source):
            opening = source[index + 2]
            closing = {"[": "]", "{": "}", "(": ")", "<": ">"}.get(opening, opening)
            end = source.find(closing + "'", index + 3)
            if end < 0:
                raise AssertionError("unterminated Oracle alternative-quoted literal in test input")
            result.append(" ")
            index = end + 2
            continue
        if source[index] == "'":
            index += 1
            while index < len(source):
                if source[index] == "'":
                    if index + 1 < len(source) and source[index + 1] == "'":
                        index += 2
                        continue
                    index += 1
                    break
                index += 1
            result.append(" ")
            continue
        result.append(source[index])
        index += 1
    return "".join(result)


class EnvironmentComparisonTests(unittest.TestCase):
    def test_unreadable_selected_dictionary_section_blocks_readiness(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload in (source, target):
            payload["coverage"]["sections"]["tables"] = {
                "complete": False, "pages": [0], "reason": "dictionary section is unavailable",
            }
            payload["sections"]["tables"] = []
            payload["unavailable"] = {"tables": "dictionary section is unavailable"}

        parsed = parse_environment_catalog_output(framed(source), sections=("tables",))
        report = compare_environment_catalogs(parsed, target, sections=("tables",))

        self.assertEqual(report["exit_code"], 2)
        self.assertEqual(report["readiness"], "blocked")
        self.assertEqual(report["sections"]["tables"]["status"], "incomplete")

    def test_same_database_different_selected_schema_is_allowed(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload in (source, target):
            payload["identity"]["db_unique_name"] = "SHARED_DATABASE"
            payload["identity"]["container_id"] = "3"
            payload["identity"]["container_name"] = "APP_PDB"
        source["sections"]["tables"] = []
        target["sections"]["tables"] = []

        report = compare_environment_catalogs(source, target, sections=("tables",))

        self.assertEqual(report["exit_code"], 0)
        self.assertEqual(report["readiness"], "ready")

    def test_same_observed_database_container_schema_and_edition_is_blocked(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        target["schema"] = source["schema"]
        target["identity"] = dict(source["identity"])
        target["sections"]["tables"] = list(source["sections"]["tables"])

        report = compare_environment_catalogs(source, target, sections=("tables",))

        self.assertEqual(report["exit_code"], 2)
        self.assertEqual(report["readiness"], "blocked")
        self.assertTrue(any(item["section"] == "identity" for item in report["blockers"]))

    def test_timestamp_timezone_precision_is_part_of_the_column_type(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload, precision in ((source, 9), (target, 6)):
            payload["sections"]["columns"] = [{
                "table_name": "T_SHARED", "name": "CREATED_AT",
                "column_position": 1, "user_generated": "YES",
                "data_type": f"TIMESTAMP({precision}) WITH TIME ZONE",
                "data_type_mod": None, "data_type_owner": None, "data_length": 13,
                "data_precision": precision, "data_scale": 0, "char_used": None,
                "char_length": None, "nullable": "N", "hidden": "NO", "virtual": "NO",
            }]
            payload["coverage"]["sections"]["columns"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("columns",))

        self.assertEqual(report["exit_code"], 1)
        self.assertIn("data_type", report["differences"][0]["fields"])

    def test_column_ordinal_changes_are_reported_as_structural_drift(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload in (source, target):
            payload["sections"]["columns"] = [
                {"table_name": "T_ORDER", "name": "A", "data_type": "NUMBER", "column_position": 1, "user_generated": "YES", "hidden": "N"},
                {"table_name": "T_ORDER", "name": "B", "data_type": "VARCHAR2", "column_position": 2, "user_generated": "YES", "hidden": "N"},
            ]
            payload["coverage"]["sections"]["columns"] = {"complete": True, "pages": [2]}
        target["sections"]["columns"][0]["column_position"] = 2
        target["sections"]["columns"][1]["column_position"] = 1

        report = compare_environment_catalogs(source, target, sections=("columns",))

        self.assertEqual(report["exit_code"], 1, report)
        self.assertEqual(len(report["differences"]), 2)
        self.assertTrue(all("column_position" in row["fields"] for row in report["differences"]))

    def test_column_rows_without_order_evidence_block_readiness(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload in (source, target):
            payload["sections"]["columns"] = [
                {"table_name": "T_ORDER", "name": "A", "data_type": "NUMBER", "hidden": "N", "user_generated": "YES"},
            ]
            payload["coverage"]["sections"]["columns"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("columns",))

        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["sections"]["columns"]["status"], "incomplete")
        self.assertTrue(any("column position" in blocker["message"] for blocker in report["blockers"]))

    def test_capture_parser_rejects_column_rows_without_order_evidence(self) -> None:
        payload = catalog("dev")
        payload["sections"]["columns"] = [{
            "table_name": "T_ORDER", "name": "A", "data_type": "NUMBER", "hidden": "N",
            "user_generated": "YES",
        }]
        payload["coverage"]["sections"]["columns"] = {"complete": True, "pages": [1]}

        with self.assertRaisesRegex(CatalogError, "column position"):
            parse_environment_catalog_output(framed(payload), sections=("columns",))

    def test_ace_timestamp_fractional_seconds_change_is_reported(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        ace = {
            "host": "api.example.test", "lower_port": 443, "upper_port": 443,
            "principal": "APP_DEV", "principal_type": "DATABASE", "privilege": "connect",
            "grant_type": "GRANT", "inverted_principal": "NO",
            "start_date": "2026-10-14T12:30:45.123456", "end_date": None,
            "bounds_timezone_qualified": False,
        }
        source["sections"]["network-aces"] = [dict(ace)]
        target["sections"]["network-aces"] = [
            {**ace, "principal": "APP_STAGE", "start_date": "2026-10-14T12:30:45.123457"},
        ]
        for payload in (source, target):
            payload["coverage"]["sections"]["network-aces"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("network-aces",))

        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["sections"]["network-aces"]["status"], "incomplete")
        self.assertIn("start_date", report["differences"][0]["fields"])

    def test_equal_unqualified_bounded_aces_block_readiness_but_remain_compared(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        ace = {
            "host": "api.example.test", "lower_port": 443, "upper_port": 443,
            "principal": "APP_DEV", "principal_type": "DATABASE", "privilege": "connect",
            "grant_type": "GRANT", "inverted_principal": "NO",
            "start_date": "2026-10-14T12:30:45.123456", "end_date": None,
            "bounds_timezone_qualified": False,
        }
        source["sections"]["network-aces"] = [dict(ace)]
        target["sections"]["network-aces"] = [{**ace, "principal": "APP_STAGE"}]
        for payload in (source, target):
            payload["coverage"]["sections"]["network-aces"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("network-aces",))

        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["sections"]["network-aces"]["status"], "incomplete")
        self.assertEqual(len(report["identical"]), 1)
        self.assertTrue(any("timezone" in blocker["message"].lower() for blocker in report["blockers"]))

    def test_timezone_qualified_recorded_ace_bounds_compare_without_blocking(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        ace = {
            "host": "api.example.test", "lower_port": 443, "upper_port": 443,
            "principal": "APP_DEV", "principal_type": "DATABASE", "privilege": "connect",
            "grant_type": "GRANT", "inverted_principal": "NO",
            "start_date": "2026-10-14T12:30:45.123456+00:00",
            "end_date": "2026-10-15T12:30:45.654321+00:00",
        }
        source["sections"]["network-aces"] = [dict(ace)]
        target["sections"]["network-aces"] = [{**ace, "principal": "APP_STAGE"}]
        for payload in (source, target):
            payload["coverage"]["sections"]["network-aces"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("network-aces",))

        self.assertEqual(report["exit_code"], 0, report)
        self.assertEqual(len(report["identical"]), 1)

    def test_mle_module_without_language_evidence_blocks_readiness(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload in (source, target):
            payload["sections"]["java-mle"] = [{
                "name": "ORDERS_MODULE", "type": "MLE MODULE", "status": "VALID", "language": None,
            }]
            payload["coverage"]["sections"]["java-mle"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("java-mle",))

        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["sections"]["java-mle"]["status"], "incomplete")
        self.assertTrue(any("MLE module language" in blocker["message"] for blocker in report["blockers"]))

    def test_capture_parser_rejects_mle_module_without_language_evidence(self) -> None:
        payload = catalog("dev")
        payload["sections"]["java-mle"] = [{
            "name": "ORDERS_MODULE", "type": "MLE MODULE", "status": "VALID", "language": None,
        }]
        payload["coverage"]["sections"]["java-mle"] = {"complete": True, "pages": [1]}

        with self.assertRaisesRegex(CatalogError, "MLE module language"):
            parse_environment_catalog_output(framed(payload), sections=("java-mle",))

    def test_unavailable_mle_language_catalog_blocks_readiness(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload in (source, target):
            payload["sections"]["java-mle"] = []
            payload["coverage"]["sections"]["java-mle"] = {
                "complete": False, "pages": [0], "reason": "MLE language catalog is unavailable",
            }
            payload["unavailable"] = {**payload.get("unavailable", {}), "java-mle": "MLE language catalog is unavailable"}

        report = compare_environment_catalogs(source, target, sections=("java-mle",))

        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["sections"]["java-mle"]["status"], "incomplete")

    def test_view_and_source_hashes_chain_ordered_body_lines(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8")
        upper = sql.upper()
        view_start = upper.index("PROCEDURE FINGERPRINT(")
        view_end = upper.index("PROCEDURE HASH_TEXT_CLOB(", view_start)
        view_fingerprint = upper[view_start:view_end]
        source_start = upper.index("PROCEDURE FINGERPRINT_SOURCE(")
        source_end = upper.index("PROCEDURE APPEND_ROWS(", source_start)
        source_fingerprint = upper[source_start:source_end]

        def roll_body_lines(lines: tuple[str, ...]) -> int:
            state = 0
            for line_number, line in enumerate(lines, start=2):
                state = zlib.crc32(f"{line_number}:{line}".encode(), state)
            return state

        self.assertNotEqual(roll_body_lines(("first body line", "second body line")),
                            roll_body_lines(("second body line", "first body line")))

        for fingerprint in (view_fingerprint, source_fingerprint):
            with self.subTest(procedure="view" if fingerprint is view_fingerprint else "stored source"):
                self.assertRegex(fingerprint, r"ORA_HASH\(.*?,\s*4294967295,\s*HASH_STATE\)")
                self.assertIn("HASH_STATE := LINE_HASH", fingerprint)
                self.assertNotRegex(fingerprint, r"P_HASH_SUM\s*:=\s*P_HASH_SUM\s*\+\s*LINE_HASH")

        self.assertIn("TO_CHAR(P_LINE_COUNT", view_fingerprint)
        self.assertIn("TO_CHAR(SOURCE_LINE", source_fingerprint)
        self.assertIn("ORA_HASH(CURRENT_LINE, 4294967295, HASH_STATE)", view_fingerprint)
        self.assertIn("ORA_HASH(SOURCE_TEXT, 4294967295, HASH_STATE)", source_fingerprint)
        self.assertIn("IF P_LINE_COUNT > 1", view_fingerprint)
        self.assertIn("IF SOURCE_LINE > 1", source_fingerprint)

    def test_column_capture_emits_ordinal_and_user_origin_evidence(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8").upper()

        self.assertIn("'COLUMN_POSITION' VALUE C.COLUMN_ID", sql)
        self.assertIn("'USER_GENERATED' VALUE C.USER_GENERATED", sql)

    def test_ace_capture_preserves_timestamp6_fraction_without_inventing_timezone(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8").upper()
        normalized_sql = " ".join(sql.split())

        self.assertIn("TO_CHAR(A.START_DATE, 'YYYY-MM-DD\"T\"HH24:MI:SS.FF6')", sql)
        self.assertIn("TO_CHAR(A.END_DATE, 'YYYY-MM-DD\"T\"HH24:MI:SS.FF6')", sql)
        self.assertIn(
            "'BOUNDS_TIMEZONE_QUALIFIED' VALUE CASE WHEN A.START_DATE IS NULL AND A.END_DATE IS NULL",
            normalized_sql,
        )
        self.assertNotIn("TZH:TZM", sql)

    def test_mle_capture_reads_language_and_fails_closed_when_it_cannot(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8").upper()
        helper_start = sql.index("PROCEDURE ADD_JAVA_MLE IS")
        helper_end = sql.index("PROCEDURE ADD_ORDS IS", helper_start)
        helper = sql[helper_start:helper_end]

        self.assertIn("JOIN ALL_MLE_MODULES", helper)
        self.assertIn("M.LANGUAGE_NAME", helper)
        self.assertIn("IF LANGUAGE_ROW_COUNT != MLE_MODULE_COUNT", helper)
        self.assertIn("IF MLE_MODULE_COUNT = 0", helper)
        self.assertIn("MLE MODULE LANGUAGE METADATA IS UNAVAILABLE", helper)
        self.assertIn("ADD_UNAVAILABLE('JAVA-MLE'", helper)

    def test_capture_environment_catalog_runs_read_only_fake_sqlcl_protocol(self) -> None:
        payload = catalog("dev")
        target = Target("dev", "fake-dev", "APP_DEV", "APP_DEV", "development")

        def fake_runner(observed_target, driver_path, run_dir, **kwargs):
            driver = Path(driver_path).read_text(encoding="utf-8")
            self.assertIn("SET TRANSACTION READ ONLY;", driver)
            self.assertIn("ALTER SESSION DISABLE COMMIT IN PROCEDURE;", driver)
            self.assertIn("EXIT SUCCESS ROLLBACK", driver)
            self.assertEqual(kwargs.get("phase"), "inventory")
            return type("Result", (), {"output": framed(payload)})()

        with tempfile.TemporaryDirectory() as temporary:
            captured = capture_environment_catalog(
                target, "dev", ("tables",), Path(temporary), _runner=fake_runner,
            )

        self.assertEqual(captured["sections"]["tables"], payload["sections"]["tables"])

    def test_capture_environment_catalog_runs_through_fake_sqlcl_process(self) -> None:
        payload = catalog("dev")
        target = Target("dev", "fake-dev", "APP_DEV", "APP_DEV", "development")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_bin = fake_sqlcl.install(
                root / "bin",
                'driver="${@: -1}"\n'
                '[[ "$driver" == @* ]] || exit 8\n'
                'grep -q "SET TRANSACTION READ ONLY;" "${driver#@}" || exit 9\n'
                'printf "%s" "$FAKE_OUTPUT"\n',
            )
            environment = fake_sqlcl.environment(fake_bin, FAKE_OUTPUT=framed(payload))

            with patch.dict(os.environ, environment, clear=True):
                captured = capture_environment_catalog(
                    target, "dev", ("tables",), root / "runs",
                )

        self.assertEqual(captured["sections"]["tables"], payload["sections"]["tables"])

    def test_environment_driver_always_supplies_all_nine_sqlcl_arguments(self) -> None:
        target = Target("dev", "docker-demo2", "APP_OWNER", "APP_OWNER", "development")
        with tempfile.TemporaryDirectory() as temporary:
            for dba_capture in (False, True):
                with self.subTest(dba_capture=dba_capture):
                    driver = _environment_driver(
                        Path(temporary), target, "dev", ("ords",), dba_capture=dba_capture,
                    )
                    invocation = next(
                        line for line in driver.read_text(encoding="utf-8").splitlines()
                        if line.startswith("@@compare_env_catalog.sql ")
                    )
                    arguments = invocation.split()[1:]

                    self.assertEqual(len(arguments), 9, invocation)
                    self.assertEqual(arguments[0], "4150505F4F574E4552")
                    self.assertEqual(arguments[1], "4150505F4F574E4552")
                    self.assertEqual(arguments[2], "646576")
                    self.assertTrue(all(arguments), invocation)

    def test_catalog_fixture_covers_every_documented_section(self) -> None:
        self.assertEqual(
            COMPARE_ENV_SECTIONS,
            (
                "tables", "columns", "constraints", "indexes", "triggers", "sequences", "synonyms",
                "views", "stored-code", "invalid-objects", "identity-columns", "object-grants",
                "system-privileges", "roles", "network-aces", "ords", "java-mle",
                "installed-options", "versions",
            ),
        )

    def test_records_are_matched_by_name_and_report_all_difference_classes(self) -> None:
        report = compare_environment_catalogs(
            catalog("dev"), catalog("staging"),
            sections=("tables", "constraints", "triggers"),
        )
        observed = {(row["section"], row["classification"], row["name"]) for row in report["differences"]}
        self.assertIn(("tables", "missing on target", "T_FROM_ONLY"), observed)
        self.assertIn(("tables", "only on target", "T_TARGET_ONLY"), observed)
        self.assertIn(("constraints", "different", "CK_STATE"), observed)
        self.assertIn(("triggers", "different", "TRG_AUDIT"), observed)
        check_difference = next(row for row in report["differences"] if row["name"] == "CK_STATE")
        trigger_difference = next(row for row in report["differences"] if row["name"] == "TRG_AUDIT")
        self.assertIn("condition", check_difference["fields"])
        self.assertIn("source_hash", trigger_difference["fields"])
        self.assertTrue(any(row["section"] == "tables" and row["name"] == "T_SHARED" for row in report["identical"]))
        self.assertTrue(any(row["section"] == "constraints" and row["name"] == "SYS_C100 / SYS_C900" for row in report["identical"]))

    def test_system_generated_constraint_names_do_not_create_a_difference(self) -> None:
        report = compare_environment_catalogs(
            catalog("dev"), catalog("staging"), sections=("constraints",),
        )
        self.assertFalse(any(row["name"] in {"SYS_C100", "SYS_C900"} for row in report["differences"]))
        self.assertTrue(any(row["classification"] == "identical" and row["source"]["name"] == "SYS_C100" for row in report["identical"]))

    def test_trigger_source_hash_detects_logic_change_while_ignoring_first_line(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        old_headers = (source["sections"]["triggers"][0]["source_header"], target["sections"]["triggers"][0]["source_header"])
        self.assertNotEqual(*old_headers)
        report = compare_environment_catalogs(source, target, sections=("triggers",))
        difference = report["differences"][0]
        self.assertEqual(difference["name"], "TRG_AUDIT")
        self.assertNotEqual(difference["source"]["source_hash"], difference["target"]["source_hash"])

    def test_trigger_header_formatting_alone_is_not_a_logic_difference(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        target["sections"]["triggers"][0]["source_hash"] = source["sections"]["triggers"][0]["source_hash"]
        report = compare_environment_catalogs(source, target, sections=("triggers",))
        self.assertEqual(report["differences"], [])
        self.assertEqual(report["identical"][0]["name"], "TRG_AUDIT")

    def test_ords_handler_source_hash_distinguishes_first_line_and_late_body_changes(self) -> None:
        cases = (
            ("first line", 101, 102, 4, 4, 45, 45),
            ("late body", 201, 202, 4, 4, 45, 45),
        )
        for label, left_hash, right_hash, left_lines, right_lines, left_length, right_length in cases:
            with self.subTest(change=label):
                source = catalog("dev")
                target = catalog("staging")
                for payload, fingerprint in (
                    (source, (left_hash, left_lines, left_length)),
                    (target, (right_hash, right_lines, right_length)),
                ):
                    source_hash, line_count, source_length = fingerprint
                    payload["sections"]["ords"] = [{
                        "kind": "handler", "module_name": "app.api", "uri_template": "items/:id",
                        "method": "GET", "source_type": "plsql/block", "items_per_page": 0,
                        "mime_type": None, "format": "json", "status": "PUBLISHED",
                        "source_hash": source_hash, "line_count": line_count,
                        "source_length": source_length, "source_complete": True,
                    }]
                    payload["coverage"]["sections"]["ords"] = {"complete": True, "pages": [1]}

                report = compare_environment_catalogs(source, target, sections=("ords",))

                self.assertEqual(report["exit_code"], 1, report)
                self.assertEqual(report["differences"][0]["name"], "handler/app.api/items/:id/GET")
                self.assertIn("source_hash", report["differences"][0]["fields"])

    def test_ords_handler_without_a_complete_source_fingerprint_blocks_readiness(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        handler = {
            "kind": "handler", "module_name": "app.api", "uri_template": "items/:id",
            "method": "GET", "source_type": "plsql/block", "items_per_page": 0,
            "mime_type": None, "format": "json", "status": "PUBLISHED",
            "source_hash": None, "line_count": None, "source_length": None,
            "source_complete": False,
        }
        for payload in (source, target):
            payload["sections"]["ords"] = [dict(handler)]
            payload["coverage"]["sections"]["ords"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("ords",))

        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["sections"]["ords"]["status"], "incomplete")
        self.assertTrue(any("source fingerprint" in blocker["message"] for blocker in report["blockers"]))

    def test_ords_all_newline_and_empty_sources_have_distinct_complete_metadata(self) -> None:
        cases = (
            ("newline-only", 3_731_211_719, 20_000, 20_000),
            ("empty", 0, 0, 0),
        )
        for label, source_hash, line_count, source_length in cases:
            with self.subTest(source=label):
                source = catalog("dev")
                target = catalog("staging")
                handler = {
                    "kind": "handler", "module_name": "app.api", "uri_template": "items/:id",
                    "method": "GET", "source_type": "plsql/block", "items_per_page": 0,
                    "mimes_allowed": None, "status": "PUBLISHED",
                    "source_hash": source_hash, "line_count": line_count,
                    "source_length": source_length, "source_complete": True,
                }
                for payload in (source, target):
                    payload["sections"]["ords"] = [dict(handler)]
                    payload["coverage"]["sections"]["ords"] = {"complete": True, "pages": [1]}

                report = compare_environment_catalogs(source, target, sections=("ords",))

                self.assertEqual(report["exit_code"], 0, report)
                self.assertEqual(report["identical"][0]["name"], "handler/app.api/items/:id/GET")

    def test_ords_handler_cannot_be_complete_with_a_missing_line_count(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        handler = {
            "kind": "handler", "module_name": "app.api", "uri_template": "items/:id",
            "method": "GET", "source_type": "plsql/block", "items_per_page": 0,
            "mimes_allowed": None, "status": "PUBLISHED",
            "source_hash": 3_731_211_719, "line_count": None,
            "source_length": 20_000, "source_complete": True,
        }
        for payload in (source, target):
            payload["sections"]["ords"] = [dict(handler)]
            payload["coverage"]["sections"]["ords"] = {"complete": True, "pages": [1]}

        report = compare_environment_catalogs(source, target, sections=("ords",))

        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["sections"]["ords"]["status"], "incomplete")
        self.assertTrue(any("source fingerprint" in blocker["message"] for blocker in report["blockers"]))

    def test_compare_env_hash_adapter_uses_sql_and_bounds_complete_unicode_clob_reads(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8")
        executable = _without_sql_literals(sql).upper()
        upper_sql = sql.upper()
        self.assertIn("PROCEDURE HASH_TEXT_CLOB(", upper_sql)
        self.assertIn("PROCEDURE ADD_ORDS IS", upper_sql)
        fingerprint_start = upper_sql.index("PROCEDURE FINGERPRINT(")
        fingerprint_end = upper_sql.index("PROCEDURE FINGERPRINT_SOURCE(", fingerprint_start)
        fingerprint = upper_sql[fingerprint_start:fingerprint_end]
        clob_start = upper_sql.index("PROCEDURE HASH_TEXT_CLOB(")
        clob_end = upper_sql.index("PROCEDURE APPEND_ROWS(", clob_start)
        clob_hash = upper_sql[clob_start:clob_end]
        handler_start = upper_sql.index("PROCEDURE ADD_ORDS IS")
        handler_end = upper_sql.index("PROCEDURE ADD_BASELINE_DATA IS", handler_start)
        handler_capture = upper_sql[handler_start:handler_end]

        self.assertNotRegex(fingerprint, r"P_HASH_SUM\s*:=\s*P_HASH_SUM\s*\+\s*LINE_HASH")
        self.assertRegex(fingerprint, r"SELECT\s+ORA_HASH\s*\(.*?,\s*4294967295,\s*HASH_STATE\)\s+INTO\s+LINE_HASH\s+FROM\s+DUAL")
        self.assertNotRegex(executable, r"\bFROM\s+DBA_OBJECTS\b")
        self.assertIn("DBMS_LOB.SUBSTR(P_SOURCE, C_CHUNK_UNITS, OFFSET_VALUE)", clob_hash)
        self.assertIn("CONSUMED_UNITS := LENGTH2(CHUNK_VALUE)", clob_hash)
        self.assertIn("CONSUMED_BYTES := LENGTHB(CHUNK_VALUE)", clob_hash)
        self.assertIn("OFFSET_VALUE := OFFSET_VALUE + CONSUMED_UNITS", clob_hash)
        self.assertIn("FINAL_CHARACTER := SUBSTR(CHUNK_VALUE, -1, 1)", clob_hash)
        self.assertIn("NVL(LENGTH2(REPLACE(CHUNK_VALUE, CHR(10), '')), 0)", clob_hash)
        self.assertIn(
            "IF P_SOURCE_HASH IS NULL OR P_LINE_COUNT IS NULL OR P_SOURCE_LENGTH IS NULL THEN",
            clob_hash,
        )
        self.assertNotIn("DBMS_LOB.SUBSTR(P_SOURCE, 1, TEXT_LENGTH)", clob_hash)
        self.assertIn("SELECT ORA_HASH(CHUNK_VALUE", clob_hash)
        self.assertIn("DBMS_LOB.GETLENGTH(P_SOURCE)", clob_hash)
        self.assertIn("HASH_TEXT_CLOB(ORDS_SOURCE", handler_capture)
        self.assertIn("SOURCE_COMPLETE", handler_capture)
        self.assertIn("SOURCE_LENGTH", handler_capture)
        self.assertIn("S.PARSING_SCHEMA", handler_capture)
        self.assertIn("U.TYPE", handler_capture)
        self.assertIn("U.PATTERN", handler_capture)
        self.assertIn("H.MIMES_ALLOWED", handler_capture)
        self.assertNotIn("M.MODULE_TYPE", handler_capture)
        self.assertNotIn("H.MIMETYPE", handler_capture)
        self.assertNotIn("H.FORMAT", handler_capture)
        self.assertNotIn("S.SCHEMA", handler_capture)
        self.assertIn("KIND_PAGES.APPEND(ORDS_PAGE_COUNT)", handler_capture)
        self.assertIn("ORDS_KIND_PAGES.PUT(P_KIND, KIND_PAGES)", handler_capture)
        self.assertIn("MOD(ORDS_TOTAL, C_PAGE_SIZE) = 0", handler_capture)
        self.assertIn("L_PAGE.PUT('KINDPAGES', ORDS_KIND_PAGES)", handler_capture)

    def test_oracle_clob_offset_contract_counts_supplementary_characters_as_two_units(self) -> None:
        emoji = "\U0001F600"
        self.assertEqual(len(emoji), 1)
        self.assertEqual(len(emoji.encode("utf-16-le")) // 2, 2)
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8").upper()

        self.assertIn("CONSUMED_UNITS := LENGTH2(CHUNK_VALUE)", sql)
        self.assertIn("OFFSET_VALUE := OFFSET_VALUE + CONSUMED_UNITS", sql)

    def test_compare_env_view_ddl_session_toggle_is_scoped_and_restored(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8").upper()
        helper_start = sql.index("FUNCTION READ_VIEW_DDL(")
        helper_end = sql.index("PROCEDURE FINGERPRINT(", helper_start)
        helper = sql[helper_start:helper_end]
        enable = "EXECUTE IMMEDIATE 'ALTER SESSION ENABLE COMMIT IN PROCEDURE'"
        disable = "EXECUTE IMMEDIATE 'ALTER SESSION DISABLE COMMIT IN PROCEDURE'"
        exception_start = helper.index("EXCEPTION")
        exception_end = helper.index("END;", exception_start)

        self.assertEqual(sql.count("DBMS_METADATA.GET_DDL("), 1)
        self.assertIn("DBMS_METADATA.GET_DDL('VIEW', P_VIEW_NAME, C_SCHEMA)", helper)
        self.assertEqual(helper.count(enable), 1)
        self.assertEqual(helper[exception_start:exception_end].count(disable), 1)
        self.assertEqual(helper[exception_end:].count(disable), 1)
        self.assertIn("RAISE;", helper[exception_start:])

    def test_ords_nonhandler_rows_use_supported_null_clob_expression(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8").upper()

        self.assertNotIn("CAST(NULL AS CLOB)", sql)
        self.assertEqual(sql.count("TO_CLOB(NULL)"), 3)

    def test_unselected_prefix_grants_are_not_reported(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        source["sections"]["object-grants"].append({
            "owner": "APP_DEV", "object_name": "ERP_LOAD", "grantee": "ETL_ROLE",
            "privilege": "SELECT", "grantable": "NO",
        })
        report = compare_environment_catalogs(
            source, target, sections=("object-grants",), prefixes=("HR_",),
        )
        self.assertEqual(report["differences"], [])

    def test_different_reference_and_application_rows_do_not_change_structure_readiness(self) -> None:
        source = catalog("dev")
        target = json.loads(json.dumps(source))
        target["environment"] = "staging"
        target["schema"] = "APP_STAGE"
        target["identity"]["session_user"] = "APP_STAGE"
        target["identity"]["current_schema"] = "APP_STAGE"
        target["reference_rows"] = [{"id": 900, "label": "Changed"}]
        source["reference_rows"] = [{"id": 1, "label": "Original"}]
        target["erp_camp_rows"] = [{"id": 100, "value": "different"}]
        source["erp_camp_rows"] = [{"id": 2, "value": "source"}]
        report = compare_environment_catalogs(source, target, sections=("tables",))
        self.assertEqual(report["exit_code"], 0)
        self.assertEqual(len(report["identical"]), len(source["sections"]["tables"]))
        self.assertFalse(any(row["section"] in {"reference-data", "application-data"} for row in report["differences"]))

    def test_star_prefix_includes_all_object_grants(self) -> None:
        report = compare_environment_catalogs(
            catalog("dev"), catalog("staging"), sections=("object-grants",), prefixes=("*",),
        )
        self.assertEqual(len(report["differences"]), 1)
        self.assertEqual(report["differences"][0]["classification"], "missing on target")

    def test_missing_dba_connection_is_an_explicit_blocker(self) -> None:
        report = compare_environment_catalogs(
            catalog("dev"), catalog("staging"), sections=("system-privileges",),
            dba_connections={"dev": False, "staging": False},
        )
        self.assertEqual(report["exit_code"], 2)
        self.assertEqual(report["blockers"][0]["message"], "not compared (no DBA connection)")

    def test_invalid_objects_block_readiness_even_when_both_sides_match(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        for payload in (source, target):
            payload["sections"]["invalid-objects"] = [{"name": "BROKEN_VIEW", "type": "VIEW", "status": "INVALID"}]
            payload["coverage"]["sections"]["invalid-objects"] = {"complete": True, "pages": [1]}
        report = compare_environment_catalogs(source, target, sections=("invalid-objects",))
        self.assertEqual(report["exit_code"], 2)
        self.assertTrue(any(row["name"] == "BROKEN_VIEW" for row in report["blockers"]))

    def test_paged_capture_with_more_than_one_page_is_complete(self) -> None:
        payload = catalog("dev")
        rows = [{"name": f"TABLE_{index:04d}", "temporary": "N", "partitioned": "N"} for index in range(501)]
        payload["sections"]["tables"] = rows
        payload["coverage"]["sections"]["tables"] = {"complete": True, "pages": [500, 1]}
        parsed = parse_environment_catalog_output(framed(payload), sections=("tables",))
        self.assertEqual(len(parsed["sections"]["tables"]), 501)
        target = json.loads(json.dumps(parsed))
        target["environment"] = "staging"
        target["schema"] = "APP_STAGE"
        target["identity"]["session_user"] = "APP_STAGE"
        target["identity"]["current_schema"] = "APP_STAGE"
        report = compare_environment_catalogs(parsed, target, sections=("tables",))
        self.assertEqual(len(report["identical"]), 501)
        self.assertEqual(report["exit_code"], 0)

    def test_ords_capture_validates_combined_and_per_kind_page_boundaries(self) -> None:
        kinds = ("schema", "module", "template", "handler")

        def payload_with(rows: list[dict], pages: list[int], kind_pages: dict[str, list[int]]) -> dict:
            payload = catalog("dev")
            payload["sections"]["ords"] = rows
            payload["coverage"]["sections"]["ords"] = {
                "complete": True, "pages": pages, "kindPages": kind_pages,
            }
            return payload

        four_rows = [
            {"kind": "schema", "name": "APP"},
            {"kind": "module", "name": "app.api"},
            {"kind": "template", "name": "items"},
            {"kind": "handler", "name": "GET items"},
        ]
        small_kind_pages = {kind: [1] for kind in kinds}
        parsed = parse_environment_catalog_output(
            framed(payload_with(four_rows, [4], small_kind_pages)), sections=("ords",),
        )
        self.assertEqual(len(parsed["sections"]["ords"]), 4)

        mismatched_kind_pages = dict(small_kind_pages, handler=[0])
        with self.assertRaisesRegex(CatalogError, "ords handler page counts"):
            parse_environment_catalog_output(
                framed(payload_with(four_rows, [4], mismatched_kind_pages)), sections=("ords",),
            )

        multi_page_rows = [{"kind": "module", "name": f"M{index}"} for index in range(501)] + [
            {"kind": kind, "name": kind} for kind in ("schema", "template", "handler")
        ]
        multi_page_kind_pages = {"schema": [1], "module": [500, 1], "template": [1], "handler": [1]}
        parse_environment_catalog_output(
            framed(payload_with(multi_page_rows, [500, 4], multi_page_kind_pages)), sections=("ords",),
        )

        exact_page_rows = [{"kind": "module", "name": f"M{index}"} for index in range(500)]
        exact_page_kind_pages = {"schema": [0], "module": [500, 0], "template": [0], "handler": [0]}
        parse_environment_catalog_output(
            framed(payload_with(exact_page_rows, [500, 0], exact_page_kind_pages)), sections=("ords",),
        )
        empty_kind_pages = {kind: [0] for kind in kinds}
        parse_environment_catalog_output(
            framed(payload_with([], [0], empty_kind_pages)), sections=("ords",),
        )

    def test_baseline_data_capture_preserves_oracle_number_precision(self) -> None:
        payload = catalog("dev")
        exact_number = "12345678901234567890.12345678901234567890"
        payload["sections"]["baseline-data"] = [{
            "name": "APP_NUMBERS", "complete": True, "rowCount": 1, "pages": [1],
            "identity": None,
            "columns": [{"name": "AMOUNT", "data_type": "NUMBER"}],
            "rows": [{"AMOUNT": "DECIMAL_MARKER"}],
        }]
        payload["coverage"]["sections"]["baseline-data"] = {"complete": True, "pages": [1]}
        encoded_json = json.dumps(payload, separators=(",", ":")).replace(
            '"AMOUNT":"DECIMAL_MARKER"', f'"AMOUNT":{exact_number}',
        )
        encoded = base64.b64encode(gzip.compress(encoded_json.encode("utf-8"))).decode("ascii")
        output = "\n".join((
            "CATALOG_PAYLOAD_BEGIN:compare-env",
            "CATALOG_ENCODING:gzip-base64-v1",
            *[encoded[index:index + 120] for index in range(0, len(encoded), 120)],
            "CATALOG_PAYLOAD_END:compare-env",
            "CATALOG_VERIFIED:compare-env",
        ))

        parsed = parse_environment_catalog_output(
            output, sections=("baseline-data",), baseline_capture=True,
        )

        self.assertEqual(
            parsed["sections"]["baseline-data"][0]["rows"][0]["AMOUNT"],
            Decimal(exact_number),
        )

    def test_full_last_page_without_terminal_short_page_is_rejected(self) -> None:
        payload = catalog("dev")
        payload["sections"]["tables"] = [
            {"name": f"TABLE_{index:04d}", "temporary": "N", "partitioned": "N"}
            for index in range(500)
        ]
        payload["coverage"]["sections"]["tables"] = {"complete": True, "pages": [500]}
        with self.assertRaisesRegex(CatalogError, "final page"):
            parse_environment_catalog_output(framed(payload), sections=("tables",))

    def test_capture_that_hits_a_row_cap_is_rejected(self) -> None:
        payload = catalog("dev")
        payload["coverage"]["sections"]["tables"] = {
            "complete": False, "capHit": True, "pages": [500, 500],
        }
        with self.assertRaisesRegex(CatalogError, "cap"):
            parse_environment_catalog_output(framed(payload), sections=("tables",))

    def test_truncated_constraint_condition_blocks_readiness(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        source["sections"]["constraints"][0]["condition_truncated"] = "Y"
        report = compare_environment_catalogs(source, target, sections=("constraints",))
        self.assertEqual(report["exit_code"], 2)
        self.assertTrue(any("may be truncated" in item["message"] for item in report["blockers"]))

    def test_dba_capture_must_match_the_environment_database_scope(self) -> None:
        from scripts.compare_schema import _merge_dba_capture

        base = catalog("dev")
        privileged = catalog("dev")
        privileged["identity"]["db_unique_name"] = "WRONG_DATABASE"
        with self.assertRaisesRegex(CatalogError, "same database"):
            _merge_dba_capture(base, privileged)

    def test_catalog_sql_hashes_fetched_lines_after_line_one(self) -> None:
        sql = (ROOT / "scripts" / "compare_env_catalog.sql").read_text(encoding="utf-8")
        self.assertIn("IF source_line > 1 THEN", sql)
        self.assertIn("SELECT ORA_HASH(TO_CHAR(source_line, 'FM9999999990'), 4294967295, hash_state)", sql)
        self.assertIn("SELECT ORA_HASH(source_text, 4294967295, hash_state) INTO line_hash FROM dual", sql)
        self.assertNotIn("p_hash_sum := p_hash_sum + line_hash", sql)
        self.assertNotIn("ORA_HASH(s.text)", sql)

    def test_report_renderers_group_readiness_items_and_list_exclusions(self) -> None:
        report = compare_environment_catalogs(catalog("dev"), catalog("staging"), sections=("tables",))
        text = render_environment_report(report, "text")
        markdown = render_environment_report(report, "markdown")
        encoded = json.loads(render_environment_report(report, "json"))
        self.assertIn("Blockers", text)
        self.assertIn("Differences", markdown)
        self.assertIn("not compared", markdown)
        self.assertTrue(any("ERP and camp data" in item for item in encoded["notCompared"]))
        self.assertTrue(any(item.startswith("Sections not selected:") for item in encoded["notCompared"]))

    def test_dba_script_contains_only_additive_reviewable_statements(self) -> None:
        source = catalog("dev")
        target = catalog("staging")
        source["sections"]["system-privileges"] = [
            {"grantee": "APP_DEV", "privilege": "CREATE SESSION", "admin_option": "NO"},
        ]
        source["sections"]["roles"] = [
            {"grantee": "APP_DEV", "role": "REPORT_ROLE", "admin_option": "YES", "default_role": "YES"},
        ]
        target["sections"]["system-privileges"] = []
        target["sections"]["roles"] = []
        for payload, sys_pages, role_pages in ((source, [1], [1]), (target, [0], [0])):
            payload["coverage"]["sections"]["system-privileges"] = {"complete": True, "pages": sys_pages}
            payload["coverage"]["sections"]["roles"] = {"complete": True, "pages": role_pages}
        report = compare_environment_catalogs(
            source, target,
            sections=("object-grants", "system-privileges", "roles", "network-aces", "ords"),
        )
        script = emit_dba_script(report)
        self.assertIn('GRANT SELECT ON "APP_STAGE"."T_SHARED" TO "REPORT_ROLE"', script)
        self.assertIn('GRANT CREATE SESSION TO "APP_STAGE"', script)
        self.assertIn('GRANT "REPORT_ROLE" TO "APP_STAGE" WITH ADMIN OPTION', script)
        self.assertIn("DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE", script)
        self.assertIn("ORDS.ENABLE_SCHEMA", script)
        self.assertNotIn("REVOKE", script)
        self.assertNotIn("DROP ", script)

    def test_dba_script_refuses_inverted_or_unknown_network_aces(self) -> None:
        for inverted_principal in ("YES", None, "UNKNOWN"):
            with self.subTest(inverted_principal=inverted_principal):
                report = {
                    "source": {"schema": "APP_DEV"},
                    "target": {"schema": "APP_STAGE"},
                    "differences": [{
                        "section": "network-aces", "classification": "missing on target",
                        "source": {
                            "host": "api.example.test", "lower_port": 443, "upper_port": 443,
                            "principal": "APP_DEV", "principal_type": "DATABASE", "privilege": "connect",
                            "grant_type": "GRANT", "inverted_principal": inverted_principal,
                            "start_date": None, "end_date": None,
                        },
                    }],
                }

                script = emit_dba_script(report)

                self.assertNotIn("DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE", script)
                self.assertIn("Manual review required: inverted or unknown network ACE principal", script)

    def test_dba_script_maps_native_ords_auth_states_and_refuses_unknown_values(self) -> None:
        for native_value, expected_flag in (("ENABLED", "TRUE"), ("DISABLED", "FALSE")):
            with self.subTest(auto_rest_auth=native_value):
                report = {
                    "source": {"schema": "APP_DEV"},
                    "target": {"schema": "APP_STAGE"},
                    "differences": [{
                        "section": "ords",
                        "classification": "missing on target",
                        "source": {
                            "kind": "schema", "name": "APP_DEV", "status": "ENABLED",
                            "mapping_complete": True, "url_mapping_type": "BASE_PATH",
                            "url_mapping_pattern": "app", "auto_rest_auth": native_value,
                        },
                    }],
                }

                script = emit_dba_script(report)

                self.assertIn("ORDS.ENABLE_SCHEMA", script)
                self.assertIn(f"p_auto_rest_auth => {expected_flag}", script)
                self.assertNotIn("Manual review required: incomplete ORDS URL mapping", script)

        unknown_report = {
            "source": {"schema": "APP_DEV"},
            "target": {"schema": "APP_STAGE"},
            "differences": [{
                "section": "ords", "classification": "missing on target",
                "source": {
                    "kind": "schema", "name": "APP_DEV", "status": "ENABLED",
                    "mapping_complete": True, "url_mapping_type": "BASE_PATH",
                    "url_mapping_pattern": "app", "auto_rest_auth": "UNKNOWN",
                },
            }],
        }

        refused_script = emit_dba_script(unknown_report)

        self.assertNotIn("ORDS.ENABLE_SCHEMA", refused_script)
        self.assertIn("Manual review required: incomplete ORDS URL mapping", refused_script)

class EnvironmentComparisonCliTests(unittest.TestCase):
    values = {
        "DB_ENVIRONMENT": "development",
        "CODE_SQLCL_CONNECTION": "DEV",
        "CODE_EXPECTED_USER": "APP_DEV",
        "CODE_SCHEMA": "APP_DEV",
        "STAGING_SQLCL_CONNECTION": "STAGE",
        "STAGING_EXPECTED_USER": "APP_STAGE",
        "STAGING_SCHEMA": "APP_STAGE",
    }

    def test_compare_env_cli_checks_sqlcl_before_catalog_capture(self) -> None:
        order: list[str] = []
        stdout = io.StringIO()
        stderr = io.StringIO()

        def check_version() -> None:
            order.append("version")

        def capture(target, environment, sections, run_dir, **kwargs):
            order.append(f"capture:{environment}")
            return catalog(environment)

        with (
            tempfile.TemporaryDirectory() as temporary,
            patch.object(migration_runtime, "require_migration_sqlcl_version", side_effect=check_version),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = compare_schema.main(
                ["compare-env", "--from", "dev", "--to", "staging", "--section", "tables", "--format", "json"],
                environ=self.values,
                run_dir=Path(temporary),
                capture_environment_fn=capture,
            )

        self.assertIn(result, (0, 1), stdout.getvalue() + stderr.getvalue())
        self.assertEqual("version", order[0])
        self.assertEqual(["capture:dev", "capture:staging"], order[1:])
        self.assertEqual("", stderr.getvalue())
        self.assertIn('"readiness"', stdout.getvalue())

    def test_compare_env_cli_parser_help_is_offline(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            patch.object(migration_runtime, "require_migration_sqlcl_version") as check_version,
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = compare_schema.main(["compare-env", "--help"])

        self.assertEqual(0, result, stderr.getvalue())
        self.assertIn("Compare environment catalog", stdout.getvalue())
        self.assertIn("--section", stdout.getvalue())
        check_version.assert_not_called()

    def test_compare_env_cli_runtime_failure_stops_before_capture(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            patch.object(
                migration_runtime,
                "require_migration_sqlcl_version",
                side_effect=migration_runtime.MigrationRuntimeError("SQLcl floor required"),
            ),
            patch.object(compare_schema, "capture_environment_catalog") as capture,
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = compare_schema.main(
                ["compare-env", "--from", "dev", "--to", "staging", "--section", "tables"],
                environ=self.values,
                run_dir=Path("unused"),
            )

        self.assertEqual(2, result)
        self.assertIn("SQLcl floor required", stderr.getvalue())
        capture.assert_not_called()

    def test_compare_env_cli_capture_failure_becomes_a_blocker(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        def fail_capture(*_args, **_kwargs):
            raise CatalogError("fake catalog capture failure")

        with (
            tempfile.TemporaryDirectory() as temporary,
            patch.object(migration_runtime, "require_migration_sqlcl_version"),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = compare_schema.main(
                ["compare-env", "--from", "dev", "--to", "staging", "--section", "tables", "--format", "json"],
                environ=self.values,
                run_dir=Path(temporary),
                capture_environment_fn=fail_capture,
            )

        report = json.loads(stdout.getvalue())
        self.assertEqual(2, result)
        self.assertEqual(2, report["exit_code"])
        self.assertTrue(any("fake catalog capture failure" in item["message"] for item in report["blockers"]))
        self.assertEqual("", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
