from __future__ import annotations

import hashlib
import importlib
import unittest


class BaselineBundleTests(unittest.TestCase):
    def api(self):
        try:
            return importlib.import_module("scripts.baseline_bundle")
        except ModuleNotFoundError as exc:
            if exc.name == "scripts.baseline_bundle":
                self.fail("scripts.baseline_bundle has not been implemented")
            raise

    def component(self, api, kind, steps=(), preconditions=(), postconditions=None):
        if postconditions is None:
            postconditions = ({"id": "ready", "sql": "SELECT 1 FROM dual", "expected": 1},)
        return api.BaselineComponent(
            kind=kind,
            steps=tuple(steps),
            preconditions=tuple(preconditions),
            postconditions=tuple(postconditions),
        )

    def test_three_components_become_one_ordered_payload(self):
        api = self.api()
        sources = {
            "table": "CREATE TABLE CUSTOMER_STATUS (ID NUMBER);\n",
            "permissions": "GRANT SELECT ON CUSTOMER_STATUS TO APP_USER;\n",
            "package": "CREATE OR REPLACE PACKAGE CUSTOMER_API AS\n  PROCEDURE READ_STATUS;\nEND CUSTOMER_API;\n/\n",
        }
        components = (
            self.component(api, "code", (("001-package.sql", sources["package"]),)),
            self.component(api, "grants", (("001-permissions.sql", sources["permissions"]),)),
            self.component(api, "structure", (("001-table.sql", sources["table"]),)),
        )

        result = api.combine_baseline_components(components)

        expected_names = (
            "001-structure-table.sql",
            "002-grants-permissions.sql",
            "003-code-package.sql",
        )
        self.assertEqual(tuple(result.steps), expected_names)
        self.assertEqual(
            tuple(result.steps.values()),
            (sources["table"], sources["permissions"], sources["package"]),
        )
        self.assertEqual(
            result.provenance,
            (
                {
                    "kind": "structure",
                    "originalName": "001-table.sql",
                    "generatedName": "001-structure-table.sql",
                    "sqlSha256": hashlib.sha256(sources["table"].encode("utf-8")).hexdigest(),
                },
                {
                    "kind": "grants",
                    "originalName": "001-permissions.sql",
                    "generatedName": "002-grants-permissions.sql",
                    "sqlSha256": hashlib.sha256(sources["permissions"].encode("utf-8")).hexdigest(),
                },
                {
                    "kind": "code",
                    "originalName": "001-package.sql",
                    "generatedName": "003-code-package.sql",
                    "sqlSha256": hashlib.sha256(sources["package"].encode("utf-8")).hexdigest(),
                },
            ),
        )

    def test_all_checks_survive_with_namespaced_ids(self):
        api = self.api()
        sql = "SELECT COUNT(*) FROM user_tables WHERE table_name = 'CUSTOMER_STATUS'"
        components = (
            self.component(
                api,
                "code",
                postconditions=({"id": "ready", "sql": sql, "expected": 1},),
            ),
            self.component(
                api,
                "grants",
                postconditions=({"id": "ready", "sql": "SELECT 1 FROM dual", "expected": 1},),
            ),
            self.component(
                api,
                "structure",
                preconditions=({"id": "ready", "sql": "SELECT 1 FROM dual", "expected": 1},),
                postconditions=({"id": "ready", "sql": sql, "expected": 1},),
            ),
        )
        original_check = {"id": "ready", "sql": sql, "expected": 1}

        result = api.combine_baseline_components(components)

        self.assertEqual(
            result.checks,
            {
                "schemaVersion": 1,
                "preconditions": [
                    {"id": "structure-ready", "sql": "SELECT 1 FROM dual", "expected": 1}
                ],
                "postconditions": [
                    {"id": "structure-ready", "sql": sql, "expected": 1},
                    {"id": "grants-ready", "sql": "SELECT 1 FROM dual", "expected": 1},
                    {"id": "code-ready", "sql": sql, "expected": 1},
                ],
            },
        )
        self.assertEqual(original_check, {"id": "ready", "sql": sql, "expected": 1})

        with self.assertRaises(api.BaselineBundleError):
            api.combine_baseline_components(
                (
                    self.component(
                        api,
                        "structure",
                        postconditions=(
                            {"id": "ready", "sql": "SELECT 1 FROM dual", "expected": 1},
                            {"id": "ready", "sql": "SELECT 1 FROM dual", "expected": 1},
                        ),
                    ),
                )
            )
        with self.assertRaises(api.BaselineBundleError):
            api.combine_baseline_components(
                (
                    self.component(
                        api,
                        "structure",
                        postconditions=({"id": "ready", "sql": "DELETE FROM user_tables", "expected": 1},),
                    ),
                )
            )

    def test_data_and_changed_boundary_requirements_refuse(self):
        api = self.api()
        valid_check = {"id": "ready", "sql": "SELECT 1 FROM dual", "expected": 1}
        structure_precondition = {"id": "exists", "sql": "SELECT 1 FROM dual", "expected": 1}

        for kind in ("data", "unknown"):
            with self.subTest(kind=kind), self.assertRaises(api.BaselineBundleError):
                api.combine_baseline_components((self.component(api, kind),))

        with self.assertRaises(api.BaselineBundleError):
            api.combine_baseline_components(
                (self.component(api, "structure"), self.component(api, "structure"))
            )

        for kind in ("grants", "code"):
            with self.subTest(kind=kind), self.assertRaises(api.BaselineBundleError):
                component = self.component(api, kind, preconditions=(structure_precondition,))
                api.combine_baseline_components((component,))

        with self.assertRaises(api.BaselineBundleError):
            api.combine_baseline_components(
                (
                    self.component(
                        api,
                        "structure",
                        steps=(
                            ("001-table.sql", "CREATE TABLE T (ID NUMBER);\n"),
                            ("003-index.sql", "CREATE INDEX T_I ON T (ID);\n"),
                        ),
                        postconditions=(valid_check,),
                    ),
                )
            )

        # Structure preconditions are kept at the combined initial boundary.
        retained = api.combine_baseline_components(
            (
                self.component(
                    api,
                    "structure",
                    preconditions=(structure_precondition,),
                ),
            )
        )
        self.assertEqual(retained.checks["preconditions"][0]["id"], "structure-exists")

    def test_empty_components_and_limits(self):
        api = self.api()

        empty = api.combine_baseline_components(
            (
                self.component(api, "code"),
                self.component(api, "grants"),
                self.component(api, "structure"),
            )
        )
        self.assertEqual(empty.steps, {})
        self.assertEqual(empty.provenance, ())

        def steps(count):
            return tuple(
                (f"{index:03d}-step-{index:03d}.sql", f"CREATE TABLE T_{index:03d} (ID NUMBER);\n")
                for index in range(1, count + 1)
            )

        accepted = api.combine_baseline_components(
            (
                self.component(api, "structure", steps(333)),
                self.component(api, "grants", steps(333)),
                self.component(api, "code", steps(333)),
            )
        )
        self.assertEqual(len(accepted.steps), 999)
        self.assertEqual(tuple(accepted.steps)[-1], "999-code-step-333.sql")

        with self.assertRaises(api.BaselineBundleError):
            api.combine_baseline_components(
                (
                    self.component(api, "structure", steps(500)),
                    self.component(api, "grants", steps(500)),
                )
            )

    def test_nonempty_bundle_requires_postconditions_but_empty_bundle_is_skippable(self):
        api = self.api()
        no_work = api.combine_baseline_components(
            (
                self.component(api, "structure", postconditions=()),
                self.component(api, "grants", postconditions=()),
                self.component(api, "code", postconditions=()),
            )
        )
        self.assertEqual(no_work.steps, {})
        self.assertEqual(no_work.checks["postconditions"], [])

        with self.assertRaises(api.BaselineBundleError):
            api.combine_baseline_components(
                (
                    self.component(
                        api,
                        "structure",
                        steps=(("001-table.sql", "CREATE TABLE T (ID NUMBER);\n"),),
                        postconditions=(),
                    ),
                )
            )

    def test_invalid_unicode_check_sql_uses_bundle_error(self):
        api = self.api()
        component = self.component(
            api,
            "structure",
            postconditions=({"id": "bad-text", "sql": "SELECT '\ud800' FROM dual", "expected": 1},),
        )
        try:
            api.combine_baseline_components(
                (component,)
            )
        except api.BaselineBundleError:
            return
        except UnicodeEncodeError as exc:
            self.fail(f"surrogate check SQL escaped as UnicodeEncodeError: {exc}")
        self.fail("surrogate check SQL was not rejected")

    def test_validate_bundle_name_enforces_ascii_slug_and_length(self):
        api = self.api()
        self.assertTrue(issubclass(api.BaselineBundleError, ValueError))
        self.assertEqual(api.validate_bundle_name("customer-status"), "customer-status")
        self.assertEqual(api.validate_bundle_name("a" * 64), "a" * 64)

        for invalid in (
            "",
            "Customer-status",
            "../customer",
            "a/b",
            "a\\b",
            "a\nb",
            "éclair",
            "a-",
            "-a",
            "a--b",
            "a_b",
            "a" * 65,
        ):
            with self.subTest(name=invalid), self.assertRaises(api.BaselineBundleError):
                api.validate_bundle_name(invalid)


if __name__ == "__main__":
    unittest.main()
