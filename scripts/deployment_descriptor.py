#!/usr/bin/env python3
"""Strict APEX 26.1 deployment descriptor reader."""

from __future__ import annotations

import json
import re
from pathlib import Path


class DescriptorError(ValueError):
    """The selected deployment descriptor is invalid or incomplete."""


_FIELDS = {
    "workspace": {"name": "text"},
    "app": {"id": "id", "databaseSession": {"parsingSchema": "schema"}},
}


def _check(value: object, contract: object, path: str = "") -> None:
    if isinstance(contract, dict):
        if not isinstance(value, dict):
            raise DescriptorError(f"deployment {path or 'root'} must be an object")
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else key
            if key not in contract:
                raise DescriptorError(f"unsupported deployment property: {child_path}")
            _check(child, contract[key], child_path)
        return

    if contract == "id":
        valid = type(value) is int and 0 < value < 10**18
        description = "must be a positive integer"
    elif contract == "schema":
        valid = isinstance(value, str) and re.fullmatch(r"[A-Z][A-Z0-9_$#]{0,127}", value) is not None
        description = "must be an uppercase Oracle identifier"
    else:
        valid = (
            isinstance(value, str)
            and bool(value.strip())
            and len(value.encode("utf-8")) <= 255
            and not any(ord(char) < 32 for char in value)
        )
        description = "must be a non-empty single-line string"
    if not valid:
        raise DescriptorError(f"deployment {path} {description}")


def _get(data: dict, dotted_path: str):
    try:
        value = data
        for component in dotted_path.split("."):
            value = value[component]
        return value
    except (KeyError, TypeError):
        raise DescriptorError(f"deployment {dotted_path} is required") from None


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DescriptorError("invalid deployment descriptor: duplicate JSON property")
        result[key] = value
    return result


def _constant(_value):
    raise DescriptorError("invalid deployment descriptor: nonfinite JSON number")


def read_json(path: Path) -> dict:
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
        raise DescriptorError("deployment descriptor must not be a symbolic link")
    try:
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            raise DescriptorError("invalid deployment descriptor: it starts with a UTF-8 byte-order mark")
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs, parse_constant=_constant)
    except DescriptorError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise DescriptorError("invalid deployment descriptor: cannot read strict UTF-8 JSON") from None
    if not isinstance(data, dict):
        raise DescriptorError("deployment descriptor root must be an object")
    return data


def validate_descriptor(data: dict, app_id: int) -> None:
    _check(data, _FIELDS)
    _get(data, "workspace.name")
    selected_id = _get(data, "app.id")
    _get(data, "app.databaseSession.parsingSchema")
    if selected_id != app_id:
        raise DescriptorError(
            f'deployment app.id is {selected_id} but this is application {app_id}: '
            f'set "id": {app_id} in the descriptor'
        )


def read_descriptor(path: Path, app_id: int) -> dict:
    data = read_json(path)
    validate_descriptor(data, app_id)
    return data
