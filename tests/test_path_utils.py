"""Path containment handles equivalent Windows short-name aliases."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

try:
    from scripts.path_utils import relative_to_root
except ModuleNotFoundError:
    relative_to_root = None


class RelativeToRootTests(unittest.TestCase):
    def test_accepts_a_physical_root_alias_and_returns_only_the_suffix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "long-root-name"
            root.mkdir()
            alias = Path(temporary) / "short-root"
            candidate = alias / "scratch" / "report.json"

            def samefile(left: str | Path, right: str | Path) -> bool:
                return Path(left) == alias and Path(right) == root

            self.assertIsNotNone(relative_to_root, "the short-path-aware containment helper is missing")
            assert relative_to_root is not None
            with patch("scripts.path_utils.os.path.samefile", side_effect=samefile):
                self.assertEqual(Path("scratch/report.json"), relative_to_root(candidate, root))

    def test_alias_above_the_repository_root_does_not_count_as_a_reparse_point(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary) / "real-parent"
            root = parent / "repo"
            root.mkdir(parents=True)
            alias_parent = Path(temporary) / "parent-alias"
            candidate = alias_parent / "repo" / "scratch" / "report.json"

            def samefile(left: str | Path, right: str | Path) -> bool:
                return Path(left) == alias_parent / "repo" and Path(right) == root

            with patch("scripts.path_utils.os.path.samefile", side_effect=samefile):
                self.assertEqual(Path("scratch/report.json"), relative_to_root(candidate, root))

    def test_rejects_a_path_outside_the_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "root"
            outside = Path(temporary) / "outside" / "file.json"
            root.mkdir()
            with self.assertRaises(ValueError):
                relative_to_root(outside, root)


if __name__ == "__main__":
    unittest.main()
