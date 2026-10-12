# APEX 26.1 backport qualification

## Scope

This work is on the documented `codex/apex-26.1` release branch, based at
`5178f57a56d919337d1e7d23fc809275cfb8488e`. The qualification below records
the candidate tree built from that base plus this backport. The port keeps the
APEX 26.1 descriptor contract and does not introduce APEX 26.2 APIs. It carries
selected release-neutral migration safety improvements:
read-only verification, frozen rollout, DML rehearsal, safe next-revision
creation, honest apply-not-started classification, and stable catalog
preflight with direct synonym/grant evidence.

The separate `compare-env` and baseline-capture tools are outside this
backport's scope; they are standalone features rather than requirements for
APEX 26.1 compatibility. No APEX export/import was run.

## Qualification matrix

| Database | APEX | ORDS | SQLcl | OS | Branch / base commit | Tested scope and outcome | Cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| No database session | Not exercised | Not exercised | 26.3.0.0 installed; no live SQLcl session | Linux; Python 3.14.4 | `codex/apex-26.1`; base `5178f57a56d919337d1e7d23fc809275cfb8488e` | **Pass offline:** `python3 -m unittest discover -s tests` — 1,079 tests passed, 26 skipped. `git diff --check`, Bash syntax, Python compilation and five JSON parses passed; Ruff unavailable | No database fixture or generated database state |
| Oracle Free image `23.26.3.0` | Not confirmed as 26.1 | ORDS image `26.3.0` | 26.3.0.0 installed | Linux | `codex/apex-26.1`; base `5178f57a56d919337d1e7d23fc809275cfb8488e` | **Not-run.** Image tags do not establish an installed APEX release, and no database session was opened | No fixture created; no cleanup required |
| Windows target | Unknown | Unknown | Unknown | Windows host unavailable; available PowerShell launchers are under `/snap/bin` and excluded by the project's native-runtime tests | `codex/apex-26.1`; base `5178f57a56d919337d1e7d23fc809275cfb8488e` | **Not-run.** Windows PowerShell/runtime qualification remains open | No fixture created; no cleanup required |

## Limits and remaining gate

- The offline suite uses fake SQLcl sessions and catalog fixtures. It does not
  prove Oracle catalog SQL compiles, SQLcl 26.1 behavior, ORDS export behavior,
  APEX 26.1 import/export behavior, or Windows PowerShell behavior.
- No database, schema, application, ORDS module, or deployment target was
  changed. There is no live comparison result to report.
- The APEX 26.1 runtime row remains **not-run** until its exact database/APEX/
  ORDS/SQLcl tuple and a named disposable target are verified. Any later live
  qualification must record the tested command scope and prove fixture cleanup.
