# APEX 26.1 pre-merge shared-settings correction

The 26.2 parity review exposed an additional defect shared by both templates:
`_exact_settings_check` omitted AND between the TYPE predicate and the first
compiler-setting predicate. Generated postconditions were invalid SQL.

The correction adds that conjunction without changing the existing F1–F9/R1–R5
repairs. The new executable catalog-shaped query regression failed with a SQL
syntax error before the fix and passed afterwards for exact settings, null and
non-null compiler flags, missing rows and every scope/setting mismatch.
The approved code-check golden hash was updated for the corrected SQL.

Focused verification passed: baseline module 60 tests and the new settings
module 1 test; Ruff, Python compilation, Bash syntax, example configuration and
`git diff --check` passed. Full discovery and exact-candidate platform CI are
merge gates; final results belong to the PR and ignored
`scratch/merge-review-2026-10-16/` evidence.

Prior live qualification at `9c233a4` remains scoped to local SYS sessions on
APEX 26.1.5 and its original artifacts. This increment performs no live database
operation and does not claim a new live qualification for the settings query.
