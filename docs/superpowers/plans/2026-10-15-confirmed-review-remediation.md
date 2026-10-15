# APEX 26.1 Confirmed Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task by task, inline and without subagents. Steps use checkbox (`- [ ]`) syntax for tracking. The user’s explicit execution method takes precedence over delegation suggestions in other skills.

**Goal:** Fix all nine confirmed defects from the 2026-10-15 review and prove each repair with focused regressions and final candidate verification.

**Architecture:** Keep the current CLI, migration and receipt architecture. Reuse the existing SQLcl-aware lexer for rollout validation, put backup-manifest parsing in one small stdlib helper shared by both wrappers, and add scoped baseline postconditions. Repair configuration, upgrade metadata and optional dependency resolution without introducing a new deployment framework.

**Tech Stack:** Python >=3.10/unittest, Bash, Windows PowerShell 5.1 and PowerShell 7, Oracle SQLcl, GitHub Actions; optional Graphify.

**Spec:** [Confirmed-review remediation requirements](../specs/2026-10-15-confirmed-review-remediation.md). Read both documents before implementation. Original evidence is under `scratch/review-2026-10-15/` in the 26.1 repository.

## Global Constraints

- APEX 26.1 compatibility; do not introduce APEX 26.2 APIs or the 26.2 descriptor contract.
- Python >=3.10; operational code remains stdlib-only, with Graphify optional.
- Preserve Bash and Windows PowerShell 5.1/PowerShell 7 behavior.
- Execute inline, without subagents, using the existing checkout and a named branch; no new worktree.
- No database connections, writes, imports, exports, deployment, or shared Graphify installation changes are authorized by this planning request.
- No commits or pushes without an explicit user instruction.
- Preserve project-owned files, `.env`, app source, migrations, receipts and attempt evidence. Consult `docs/known-limitations.md` before changing behavior.
- Source files use LF. New internal helpers must be template-owned; these planning documents remain template-only under `docs/superpowers/**`.

## Review Focus

- Comment-looking text inside ordinary strings and q-quotes must stay valid ORDS handler content; Task 1 tests it.
- Backup leading zeroes, CRLF/ASCII whitespace and signed-64-bit overflow must behave identically in both shells; Task 3 tests them.
- A nullable-only delta and a bundled delta must verify the new column itself, rather than pass on unrelated checks; Task 5 tests both.
- A historical TEAM lock and a deliberately chosen custom upstream must not be silently retargeted; Task 8 tests both.
- New postconditions must pass `validate_check_query` and preserve immutable pending-attempt evidence when verification fails; Tasks 5–6 test those boundaries.

## Files and ownership

| Area | Files | Responsibility |
| --- | --- | --- |
| Rollout guards | `scripts/rollout.py`, `tests/test_rollout.py`, `tests/test_sql_driver_contracts.py` | F1–F2 lexer refusal and SQLBLANKLINES ordering. Reuse `scripts/validate_migration.py`; do not replace the ORDS exporter’s tolerant scanner globally. |
| Backup guard | New `scripts/backup_manifest.py`, new `tests/test_backup_manifest.py`; `scripts/backup_db.sh`, `scripts/backup_db.ps1`, `tests/test_backup_db_cli.py`, `tests/test_backup_ords_cli.py`, `tests/test_multi_schema_cli.py`, `tests/test_template_manifest.py` | F3 shared grammar/count validation and wrapper integration/fixture copying. |
| Baselines | `scripts/baseline.py`, `tests/test_baseline.py`, `tests/test_baseline_bundle.py`, `tests/test_baseline_bundle_cli.py`, `tests/test_migrate_cli.py` | F6–F8 exact numeric formatting, added-column checks, view validity. |
| Configuration | `scripts/load_env.sh`, `scripts/load_env.ps1`, `scripts/local_config.py`, `.env.example`, `tests/test_local_config.py`, `tests/test_env_schema_lists.py`, `tests/test_compare_env.py`, `tests/test_baseline.py` | F4 optional DBA alias parsing and supported-command coverage. |
| Upgrades/docs | `template-manifest.json`, `README.md`, `docs/GETTING_STARTED.md`, `tests/test_upgrade_template.py`, `tests/test_documentation_contract.py`, `tests/test_template_manifest.py` | F5 26.1 default upstream, old-lock recovery, ownership. |
| Dependency gate | `pyproject.toml`, `.github/workflows/database-checks.yml` | F9 correct graph extra and real resolver coverage. |

## Order and finding coverage

| Task | Finding | Depends on |
| --- | --- | --- |
| 0 | Establish candidate branch and evidence baseline | — |
| 1 | F1: rollout lexical guard | 0 |
| 2 | F2: rollout blank-line preservation | 1 |
| 3 | F3: backup manifest validation | 0 |
| 4 | F7: numeric type formatting | 0 |
| 5 | F6: added-column postconditions | 4 |
| 6 | F8: view-only validity checks | 0 |
| 7 | F4: DBA configuration keys | 0 |
| 8 | F5: release-specific upgrade upstream | 0 |
| 9 | F9: Graphify dependency and CI resolution | 0 |
| 10 | Whole-candidate verification and report | 1–9 |

Tasks are executed sequentially in this session. Their independence does not authorize delegation. Suggested task order is the table order, prioritizing the three P1 findings.

### Task 0: Establish the implementation baseline

**Files:** Read `AGENTS.md`, `AGENTS.project.md`, `.agents/rules/project.md`, `docs/known-limitations.md`, the spec, and the original review. No operational code changes in this task.

**Interfaces:** Produces a recorded base SHA and named candidate branch in this checkout, plus `scratch/review-remediation-2026-10-15/` for new evidence. The old review directory remains historical.

- [ ] Record `git status --short`, current branch/SHA and remotes; preserve the planning documents and all unrelated work.
- [ ] Fetch origin and compare its main with reviewed SHA `325b911e3c5bf3e0254ee457cd4170b184e1f35b`. If upstream moved, review the intervening diff against F1–F9 and update this plan’s baseline before implementation; do not silently apply an outdated diagnosis.
- [ ] Use a named task branch based on reviewed/current reconciled origin/main in the existing checkout. Proposed name: `codex/fix-26-1-review-findings`. Reuse it if it already exists and is appropriate; do not reset it or create a worktree. The twelve-commit local main lag must not become the implementation base.
- [ ] Save red-test/probe evidence and a per-task status record under the new scratch directory. Use `_no_real_sqlcl` and existing fake SQLcl fixtures for unit tests; never fall through to a saved connection.
- [ ] Read the applicable TDD/execution skills before implementation. Commit/push instructions in skills remain subordinate to the no-commit/no-push constraint.

### Task 1: Reject malformed SQLcl lexical input before rollout execution — F1

**Files:** Modify `scripts/rollout.py`; test `tests/test_rollout.py`. Read `scripts/validate_migration.py` and `scripts/ords_export.py`.

**Interfaces:** Keep `validate_sql_script(source: str, number: int = 1) -> None`. Consume the existing `mask_comments_and_literals(source: str, quoted_spans: list[tuple[int, int]] | None = None) -> str` as lexical validation; translate its ValueError to RolloutError carrying the step number. Keep rollout’s existing command/marker/schema checks. Do not call full `validate_sql_only`, because rollout accepts explicit COMMIT/ROLLBACK and ORDS scripts.

- [ ] Add `test_sql_script_rejects_malformed_comment_before_sqlcl`: `/*/\nPROMPT SAFE_PROBE\n*/\nSELECT 1 FROM dual;\n` must raise RolloutError; the fake SQLcl runner must remain uncalled through the supported rollout path.
- [ ] Add positive cases containing literal `/*/`, PROMPT, CONNECT and `@` inside ordinary/q-quoted handler strings, plus valid comments and explicit COMMIT/ROLLBACK. Assert acceptance and preserve existing ORDS filtering/import tests. Add malformed-comment rejection through the ORDS-import route, ensuring that route also never launches SQLcl.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_rollout`; record the new safety regression failing on baseline while positive controls pass.
- [ ] Add shared-lexer validation to the rollout validator without changing the tolerant ORDS export scanner’s global behavior or other workflows’ accepted SQL.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_rollout test_validate_migration test_ords_export test_ords_contracts`; expect exit 0 and no new skips. Inspect error text and execution-spy assertions inline.

### Task 2: Preserve blank lines inside rollout SQL — F2

**Files:** Modify `scripts/rollout.py`; test `tests/test_rollout.py`, `tests/test_sql_driver_contracts.py`.

**Interfaces:** Keep `_script_driver(...) -> Path` and its caller contract unchanged. Add `SET SQLBLANKLINES ON` before `@@payload.sql` in every generated SQL/ORDS rollout driver; retain existing rollback/commit policy and identity guards.

- [ ] Add `test_rollout_driver_enables_sqlblanklines_before_payload` using `UPDATE review_table SET flag = 1\n\nWHERE id = 1;\nCOMMIT;\n`. Assert the setting precedes the payload include and the staged payload bytes retain the blank line. Cover both sql-script and ords-import driver use.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_rollout test_sql_driver_contracts`; record the new ordering regression failing on baseline.
- [ ] Insert the setting in the common driver and rerun that command; expect exit 0.
- [ ] Re-run the original harmless parser comparison with SQLcl `/nolog`, from a private scratch directory with empty regular-file stdin. Record client parsing only: WHERE must no longer become an unknown command. Do not connect or claim affected-row counts from this check.

### Task 3: Share strict backup-manifest validation between shells — F3

**Files:** Create `scripts/backup_manifest.py`, `tests/test_backup_manifest.py`; modify both backup wrappers and fixture copy lists in `tests/test_backup_db_cli.py`, `tests/test_backup_ords_cli.py`, `tests/test_multi_schema_cli.py`; extend `tests/test_template_manifest.py`.

**Interfaces:** New stdlib-only helper exposes `parse_manifest(source: str, scope: str) -> dict[str, int]` and `verify_scope(manifest: Path, mirror: Path, scope: str) -> None`, raising `BackupManifestError(ValueError)` on refusal. CLI: `python backup_manifest.py --scope tables|code --manifest FILE --mirror DIR`; exit 0 silently on success, 2 with a plain diagnostic on refusal. `DIR` is the schema’s staged mirror containing tables/views/packages/etc. Bash uses python3; PowerShell uses the existing `Resolve-TeamPython` Path/Prefix interface and checks LASTEXITCODE.

- [ ] Add table-driven parser tests for the complete spec grammar: every required zero row; LF/CRLF; ASCII whitespace; no terminal newline; leading zeroes parsed as decimal; duplicates; unknown/cross-scope/missing types; unreadable or empty counts; extra `=`; negative/plus/decimal/exponent/Unicode digits; individual and aggregate overflow beyond `9223372036854775807`.
- [ ] Extend both-shell backup CLI tests with a committed old mirror and replacement spy. Every malformed case must exit 2, preserve old bytes, and never call replacement. Valid whitespace/CRLF cases must install. Retain all-or-nothing multi-schema and ORDS scope behavior.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_backup_db_cli` before changing wrappers; record the reproduced malformed-row failures. Run the new helper tests once created to pin their contract.
- [ ] Implement the helper using strict ASCII grammar, Python integer parsing with explicit bounds, and the existing aggregate scope-directory file count. Reject a malformed row immediately; do not accumulate type-presence evidence from an invalid row. Preserve existing missing-row and incomplete-mirror diagnostic meanings.
- [ ] Replace each wrapper’s native parser/count logic with the helper call before any install. Wire the Python resolver for PowerShell and update all named fixture copy lists so fake checkouts contain the helper. Confirm `scripts/**` owns the helper and add an ownership regression; no broad manifest glob changes are needed.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_backup_manifest test_backup_db_cli test_backup_ords_cli test_multi_schema_cli test_template_manifest`; expect exit 0. Verify failure-path preservation in both available shells, including PowerShell negative-count cancellation.

### Task 4: Preserve numeric type metadata — F7

**Files:** Modify `scripts/baseline.py`; test `tests/test_baseline.py`.

**Interfaces:** Keep `_table_column_type(row: Mapping) -> str`. It produces a faithful supported numeric type or raises BaselineError; it never substitutes an unconstrained type for a constrained source.

- [ ] Add formatter assertions: NUMBER with both attributes null -> `NUMBER`; precision 10/scale 2 -> `NUMBER(10,2)`; precision null/scale 2 -> `NUMBER(*,2)`; precision null/scale -2 -> `NUMBER(*,-2)`; FLOAT precision 63 -> `FLOAT(63)`. Cover NUMBER precision 1/38 and scale -84/127, FLOAT precision 1/126, and explicit refusal of booleans, malformed values and out-of-range attributes. Preserve existing character, RAW and temporal behavior.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_baseline`; record the new NUMBER(*,s)/FLOAT failures.
- [ ] Correct NUMBER/FLOAT formatting and numeric metadata validation in the existing helper. Where source metadata cannot specify a faithful supported form, raise BaselineError with object/column context; do not guess.
- [ ] Rerun `PYTHONPATH=tests:. python3 -m unittest -v test_baseline test_baseline_bundle_cli`; expect exit 0. Inspect emitted ADD COLUMN SQL from real builder fixtures, not only the helper’s return values.

### Task 5: Give every added column a definition postcondition — F6

**Files:** Modify `scripts/baseline.py`; test `tests/test_baseline.py`, `tests/test_baseline_bundle.py`, `tests/test_baseline_bundle_cli.py`, `tests/test_migrate_cli.py`.

**Interfaces:** Add `_column_definition_check(schema: str, row: Mapping) -> dict` using the existing check object contract `{id, sql, expected: 1}` and deterministic `_safe_check_slug`. `_structure_bundle(...)` appends one such check for every missing column. Consume Task 4’s faithful numeric formatter; use the same captured numeric semantics in verification.

- [ ] Add a nullable-only ITEMS.NOTE delta with no unrelated constraints or NOT NULL columns. Assert generated checks are nonempty, reference the new column, pass `validate_check_query`, and permit real staged-folder validation/installation. Repeat through the optional bundle composer.
- [ ] Add missing-column and wrong-type/length/precision/scale verification cases, including NUMBER(*,2) and FLOAT(63). Assert unrelated successful checks cannot make the new-column result true or create a verified receipt. Include a missing NOT NULL column so a zero-row nullable predicate alone cannot pass it.
- [ ] Run the four focused test modules above; record the nullable-only regression failing before the change.
- [ ] Emit a scoped ALL_TAB_COLS EXISTS check comparing DATA_TYPE and applicable attributes: null-safe DATA_PRECISION/DATA_SCALE for NUMBER/FLOAT; CHAR_USED plus CHAR_LENGTH for CHAR semantics or DATA_LENGTH for BYTE semantics; CHAR_LENGTH for NCHAR/NVARCHAR2; DATA_LENGTH for RAW. Use captured temporal DATA_TYPE as already formatted. Require the applicable metadata, or refuse generation rather than assume a missing field means Oracle NULL. Retain existing NOT NULL guards and explicit defaults/table-attribute exclusions.
- [ ] Rerun the four focused modules; expect exit 0, valid nonempty granular/bundled check lists, and no verified receipt on failed new-column checks. Do not change payloads or checks of an existing attempted migration to repair its historical output; new generated output follows the next revision rules.

### Task 6: Verify generated views are valid — F8

**Files:** Modify `scripts/baseline.py`; test `tests/test_baseline.py`, `tests/test_migrate_cli.py`.

**Interfaces:** Add `_view_validity_check(schema: str, name: str) -> dict`, using a deterministic `valid-view-...` ID and the existing check schema. `_code_bundle(...)` adds it for every generated view, even when no stored unit changed. Keep the existing existence check and compile-all policy; do not broaden recompilation to unrelated objects or change receipt-builder APIs.

- [ ] Add a view-only builder fixture. Assert its postconditions require the exact owner/name/VIEW row with STATUS='VALID' and no matching ALL_ERRORS ATTRIBUTE='ERROR'; every generated query must pass `validate_check_query`. Add valid, missing, INVALID, and compilation-error cases, plus an unrelated invalid object that must not fail the scoped check.
- [ ] Add a migration-runner regression where fresh view verification is false/incomplete: no success receipt, retained immutable pending-attempt evidence, and a verification-failure result. Use faithful generated-check results; do not inject `passed=True` for a query that should return false.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_baseline test_migrate_cli`; record the missing-validity regression failing.
- [ ] Add the generated validity/error postcondition to the view path and rerun those modules; expect exit 0. Preserve stored-code compiler-setting and source-byte tests.
- [ ] Record the proof boundary: synthetic invalid-view evidence exercises the guard but does not establish how Oracle returns dynamic CREATE FORCE VIEW errors. Live invalidation/read-back requires the separate target qualification in Task 10.

### Task 7: Support documented DBA aliases in `.env` — F4

**Files:** Modify `scripts/load_env.sh`, `scripts/load_env.ps1`, `scripts/local_config.py`, `.env.example`; test `tests/test_local_config.py`, `tests/test_env_schema_lists.py`, `tests/test_compare_env.py`, `tests/test_baseline.py`. Update `docs/compare-env.md` and `docs/baseline.md` where documenting precedence.

**Interfaces:** Keep existing parser/wrapper APIs. Accept optional `DEV_DBA_SQLCL_CONNECTION`, `STAGING_DBA_SQLCL_CONNECTION`, `PROD_DBA_SQLCL_CONNECTION` as scalar saved aliases. File values win; absent file keys retain externally supplied values for compatibility. Validate either source against the scalar alias regex in the spec. Do not treat them as schema-aligned lists or require new expected-user/profile triples.

- [ ] Add parser parity tests for all three keys, absent keys, explicit blank values, comma lists, whitespace, unsupported characters, duplicate keys and file-over-process precedence. Test inherited aliases without weakening the ordinary profile requirements.
- [ ] Extend supported compare-env and baseline export-grants command fixtures to put the aliases in `.env`, rather than only injecting os.environ. Fake SQLcl must show the selected environment’s DBA alias and retain the existing read-only/same-scope checks. Test that missing DBA aliases do not borrow DEV/STAGING/PROD values from one another.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_local_config test_env_schema_lists test_compare_env test_baseline`; record unsupported-setting failures on baseline.
- [ ] Add allowlist, export and validation support in all three readers, and commented credential-free examples in `.env.example`. Document the two-channel precedence so rereading a shell environment is not misrepresented as file-only configuration.
- [ ] Rerun that command plus `test_team_cli test_windows_support`; expect exit 0 and matching Bash/PowerShell outcomes. Retain runtime database-scope verification rather than trusting the DBA alias name.

### Task 8: Keep upgrades on the 26.1 release line — F5

**Files:** Modify `template-manifest.json`, `README.md`, `docs/GETTING_STARTED.md`; test `tests/test_upgrade_template.py`, `tests/test_documentation_contract.py`, `tests/test_template_manifest.py`. Read `scripts/upgrade_template.py`; its source-precedence algorithm need not change.

**Interfaces:** The default manifest upstream becomes `https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_26_1.git`. Preserve source precedence: explicit `--source` > recorded lock upstream > manifest upstream. Preserve schemaVersion 1 and refusal of an incompatible 26.2 manifest.

- [ ] Add tests that a fresh 26.1 clone resolves the 26.1 upstream and bootstrap examples name that repository. Test an existing historical TEAM lock repaired via explicit `--source https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_26_1.git`; its new lock records the chosen source after a successful fixture apply. Assert dry-run leaves bytes unchanged. A deliberately selected fork/custom lock must retain its source unless the operator overrides it.
- [ ] Run `PYTHONPATH=tests:. python3 -m unittest -v test_upgrade_template test_documentation_contract test_template_manifest`; record the release-default failure.
- [ ] Correct the manifest and active clone/bootstrap examples, leaving historical provenance and generic repository descriptions intact. Document the explicit old-lock dry-run/apply recovery commands, clean-tree prerequisite, conflict review and ordinary no-overwrite rules. Do not silently rewrite existing lock sources or relax incompatible-manifest refusal.
- [ ] Rerun the focused modules; expect exit 0. Recheck template ownership of the new helper, tests and planning documents. Exercise default-source selection with local/mock Git fixtures so it tests candidate content rather than relying on a not-yet-published remote fix.

### Task 9: Correct the Graphify distribution and test resolution — F9

**Files:** Modify `pyproject.toml`, `.github/workflows/database-checks.yml`. Graphify installation/setup scripts keep their existing CLI/package distinction.

**Interfaces:** Graph extra becomes `graph = ["graphifyy", "tree-sitter-sql"]`. No runtime dependency is added. A Linux Python 3.10 CI step resolves project extras with pip’s dry-run facility; it must not use `--no-deps` or otherwise skip the requirement under test.

- [ ] Run `uv pip compile pyproject.toml --extra graph --no-cache --no-config --default-index https://pypi.org/simple --output-file scratch/review-remediation-2026-10-15/graph-requirements.txt` and `uv lock --dry-run`; retain the original unsatisfiable-graphify failure if still present. These are resolver checks, not package installation.
- [ ] Change only the distribution name in the graph extra. Keep the command/import name `graphify` where it means the actual CLI/module; do not globally rename it or upgrade the shared tool.
- [ ] Add a CI resolution step after Python setup, using `python -m pip install --dry-run --ignore-installed --disable-pip-version-check --index-url https://pypi.org/simple '.[graph]'`. The installed CI pip must support --dry-run. Resolve/download metadata in the CI job; do not add Graphify to operational runtime requirements or execute its setup/extraction against a user project.
- [ ] Re-run the two uv commands; expect exit 0. Run the exact pip dry-run command in a disposable project/environment if available. Record Python and resolved package versions as time-sensitive evidence; dependency availability is not proven by a string-only unit test.
- [ ] Confirm the CI configuration still runs its existing Linux, Windows and macOS jobs and that the ordinary stdlib workflow works without Graphify installed. Do not check in a new lockfile merely because one was generated during investigation.

### Task 10: Verify the whole candidate and reconcile the findings

**Files:** All changed files; new evidence under `scratch/review-remediation-2026-10-15/`; update the review report with candidate results while retaining the original baseline and caveats.

**Interfaces:** Produces a final candidate SHA/worktree-state record, F1–F9 closure matrix, focused/full/CI evidence, and a separate live-qualification status. This task does not grant commit, push or database-write authority.

- [ ] Run focused regressions for all nine findings against the candidate and repeat the original reproductions with paths redirected to candidate source. Each original symptom must now be refused safely or generate the required faithful checks. Update probe expectations: a deliberately malformed manifest should fail; the view case must evaluate the new validity checks rather than blindly passing all checks.
- [ ] Run `python3 -m unittest discover -s tests -v`, `ruff check scripts tools tests`, `python3 -m compileall -q scripts tools tests`, Bash and PowerShell parser checks, example-config loading, JSON/LF checks and `git diff --check`. Save logs and actual exit codes. Test totals may grow; report real totals and every remaining skip category rather than demanding the old count.
- [ ] Review the full diff inline against the spec and known limitations. Check shared-helper packaging, fixture file lists, Python 3.10 compatibility, PowerShell Path/Prefix invocation, refusal exit statuses, scoped SQL predicates, upgrade source precedence and untouched user data. Confirm no credentials, generated fixtures, temporary locks or Graphify installation artifacts are staged accidentally.
- [ ] For a locally verified but uncommitted candidate, record HEAD plus changed-file hashes. After an explicitly requested commit/push, verify local/remote SHA parity and exact-candidate Linux/Windows/macOS CI, including the new resolver gate. Until then, label CI for the repaired candidate as not run; old green CI is baseline evidence only.
- [ ] Keep live qualification pending unless the user separately authorizes a disposable target and supplies/selects credential-free saved profiles. If authorized: prove database/container/schema/session identity; use disposable fixtures to check predicate preservation, numeric dictionary attributes, nullable-column migration verification and view invalidation; use fresh read-back connections and prove fixture cleanup. Respect immutable attempts and Oracle DDL commit boundaries. Do not run these checks on shared DEV/staging/prod by inference.
- [ ] Publish the closure matrix: F1–F9 implemented status, regression result, full-suite result, platform CI status, live qualification and open limits. Missing `.env` and placeholder PROJECT.md remain expected template state. No issue is closed solely because the overall suite is green.

## Handoff and authorization

- This document is a plan, not an implementation or release claim. All task checkboxes begin unchecked.
- Preserve the user’s inline/no-subagents method. Implementation starts only when requested; this planning turn creates documentation only.
- If implementation is requested, perform the already authorized local work and tests without repeated permission prompts. Commits/pushes and real database operations still require their explicit authorization under the repository contract.
