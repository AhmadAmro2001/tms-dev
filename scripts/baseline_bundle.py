"""Pure composition helpers for generated baseline migration components."""

from __future__ import annotations

import hashlib
import re
from collections.abc import Sequence
from dataclasses import dataclass

from .migration_manifest import CHECK_ID_RE, SQL_FILE_RE, MigrationManifestError, validate_check_query
from .validate_migration import validate_sql_only


class BaselineBundleError(ValueError):
    """A generated baseline component cannot safely be bundled."""


@dataclass(frozen=True)
class BaselineComponent:
    kind: str
    steps: tuple[tuple[str, str], ...]
    preconditions: tuple[dict, ...]
    postconditions: tuple[dict, ...]


@dataclass(frozen=True)
class BundledBaseline:
    steps: dict[str, str]
    checks: dict
    provenance: tuple[dict, ...]


_BUNDLE_NAME_RE = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*\Z", re.ASCII)
_CATEGORY_ORDER = ("structure", "grants", "code")
_CATEGORY_PREFIX = frozenset(_CATEGORY_ORDER)
_MAX_STEPS = 999


def validate_bundle_name(name: str) -> str:
    """Validate and return an ASCII migration slug of at most 64 characters."""
    if not isinstance(name, str) or len(name) > 64 or _BUNDLE_NAME_RE.fullmatch(name) is None:
        raise BaselineBundleError(
            "bundle name must be an ASCII lowercase migration slug of at most 64 characters"
        )
    return name


def _validate_check_list(kind: str, phase: str, checks: object) -> list[dict]:
    if not isinstance(checks, tuple):
        raise BaselineBundleError(f"{kind} {phase} must be a tuple of checks")

    copied: list[dict] = []
    seen: set[str] = set()
    for index, check in enumerate(checks, start=1):
        if not isinstance(check, dict) or set(check) != {"id", "sql", "expected"}:
            raise BaselineBundleError(f"{kind} {phase}[{index}] must contain exactly id, sql, and expected")
        check_id = check["id"]
        sql = check["sql"]
        expected = check["expected"]
        if not isinstance(check_id, str) or CHECK_ID_RE.fullmatch(check_id) is None:
            raise BaselineBundleError(f"{kind} {phase}[{index}] has an invalid check id")
        if check_id in seen:
            raise BaselineBundleError(f"{kind} {phase} contains duplicate check id {check_id!r}")
        if not isinstance(sql, str):
            raise BaselineBundleError(f"{kind} {phase} check {check_id!r} SQL must be a string")
        if type(expected) is not int or expected != 1:
            raise BaselineBundleError(f"{kind} {phase} check {check_id!r} expected value must be integer 1")
        try:
            validate_check_query(sql)
        except (MigrationManifestError, UnicodeEncodeError) as exc:
            raise BaselineBundleError(f"{kind} {phase} check {check_id!r}: {exc}") from exc
        seen.add(check_id)
        copied.append({"id": f"{kind}-{check_id}", "sql": sql, "expected": expected})
    return copied


def _validate_component_steps(component: BaselineComponent) -> tuple[tuple[str, str], ...]:
    if not isinstance(component.steps, tuple):
        raise BaselineBundleError(f"{component.kind} steps must be a tuple")

    validated: list[tuple[str, str]] = []
    for expected_sequence, step in enumerate(component.steps, start=1):
        if not isinstance(step, tuple) or len(step) != 2:
            raise BaselineBundleError(f"{component.kind} step {expected_sequence} must be a (name, SQL) tuple")
        original_name, sql = step
        if not isinstance(original_name, str):
            raise BaselineBundleError(f"{component.kind} step {expected_sequence} filename must be a string")
        match = SQL_FILE_RE.fullmatch(original_name)
        if match is None:
            raise BaselineBundleError(f"{component.kind} step has an invalid migration filename: {original_name!r}")
        sequence = int(match.group("sequence"))
        if sequence != expected_sequence:
            raise BaselineBundleError(
                f"{component.kind} step filenames must be consecutive from 001; "
                f"expected {expected_sequence:03d}, found {sequence:03d}"
            )
        if not isinstance(sql, str):
            raise BaselineBundleError(f"{original_name} SQL must be a string")
        if "\r" in sql or sql.startswith("\ufeff"):
            raise BaselineBundleError(f"{original_name} must use UTF-8 without a BOM and LF line endings")
        try:
            validate_sql_only(sql)
            sql.encode("utf-8")
        except (UnicodeEncodeError, ValueError) as exc:
            raise BaselineBundleError(f"{original_name}: {exc}") from exc
        validated.append((original_name, sql))
    return tuple(validated)


def combine_baseline_components(components: Sequence[BaselineComponent]) -> BundledBaseline:
    """Compose generated structure, grants and code components without side effects."""
    if not isinstance(components, Sequence) or isinstance(components, (str, bytes, bytearray)):
        raise BaselineBundleError("components must be a sequence of BaselineComponent values")

    by_kind: dict[str, BaselineComponent] = {}
    for component in components:
        if not isinstance(component, BaselineComponent):
            raise BaselineBundleError("components must contain only BaselineComponent values")
        if not isinstance(component.kind, str) or component.kind not in _CATEGORY_PREFIX:
            raise BaselineBundleError(f"unsupported baseline component kind: {component.kind!r}")
        if component.kind in by_kind:
            raise BaselineBundleError(f"duplicate baseline component kind: {component.kind}")
        by_kind[component.kind] = component

    combined_steps: dict[str, str] = {}
    combined_preconditions: list[dict] = []
    combined_postconditions: list[dict] = []
    provenance: list[dict] = []

    for kind in _CATEGORY_ORDER:
        component = by_kind.get(kind)
        if component is None:
            continue
        if kind in {"grants", "code"} and component.preconditions:
            raise BaselineBundleError(f"{kind} components cannot add initial preconditions")

        combined_preconditions.extend(_validate_check_list(kind, "preconditions", component.preconditions))
        combined_postconditions.extend(_validate_check_list(kind, "postconditions", component.postconditions))
        for original_name, sql in _validate_component_steps(component):
            if len(combined_steps) >= _MAX_STEPS:
                raise BaselineBundleError(f"a baseline bundle cannot contain more than {_MAX_STEPS} SQL steps")
            match = SQL_FILE_RE.fullmatch(original_name)
            assert match is not None  # validated above
            generated_name = f"{len(combined_steps) + 1:03d}-{kind}-{match.group('name')}.sql"
            combined_steps[generated_name] = sql
            provenance.append(
                {
                    "kind": kind,
                    "originalName": original_name,
                    "generatedName": generated_name,
                    "sqlSha256": hashlib.sha256(sql.encode("utf-8")).hexdigest(),
                }
            )

    if combined_steps and not combined_postconditions:
        raise BaselineBundleError("a nonempty baseline bundle must include at least one postcondition")

    return BundledBaseline(
        steps=combined_steps,
        checks={
            "schemaVersion": 1,
            "preconditions": combined_preconditions,
            "postconditions": combined_postconditions,
        },
        provenance=tuple(provenance),
    )
