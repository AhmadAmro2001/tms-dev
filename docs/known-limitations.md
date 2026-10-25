# Known limitations and accepted behaviour

Reviews and end-to-end test runs have reported each item below and the maintainers
decided to keep it. **Do not report these again as defects, and do not "fix" them**,
unless the behaviour no longer matches this page or a change makes the risk worse.
Then report that difference. Each entry says why it is kept and what to do instead.

## Workflow decisions

| Behaviour | Why it is kept | What to do |
| --- | --- | --- |
| `publish` imports the files in the app folder whether or not they are committed. | The shared DEV database is the source of truth; Git records it. | Commit your edit and the stamped `application.apx` after publishing, before your next `export` of that app (export refuses to write over uncommitted files). |
| Two developers publishing the same app at the same instant can both import; there is no lock. | `AGENTS.md` forbids team mutexes, checkout rosters and metadata tables. | Tell the team which app you are publishing. The drift guard catches every import that is not simultaneous. |
| The first publish of an app made with `apex generate` stops at the post-import byte check and records no baseline. | Loosening the exact-bytes check for that case would weaken the main safety guard. | Follow "A new app from `apex generate`" in [publish-rules.md](publish-rules.md): commit, export, commit, publish again. |
| The drift guard cannot see unsaved edits in an open Builder page. | APEX records only saved changes. | Ask teammates before publishing a shared app. |

## Checks and their reach

| Behaviour | Why it is kept | What to do |
| --- | --- | --- |
| A statement run directly in the session uses the login's privileges, so a missing owner grant is not caught for that statement in acts-as-schema mode. | The mode supports logins that cannot use the schema owner's credentials. | Rehearse in an environment with the owner login when owner-grant fidelity for directly-run statements matters; see [login-acts-as-schema.md](login-acts-as-schema.md). |
| `dev-test` and `backup-ords` refuse a login that is not the selected schema owner. | Fixture execution and ORDS export require the actual session user to be the owner; `CURRENT_SCHEMA` does not change `SESSION_USER`. | Use an owner login for those commands; see [dev-test.md](dev-test.md#limits-and-safe-use), [ords-export.md](ords-export.md), and [login-acts-as-schema.md](login-acts-as-schema.md). |
| `check-conflicts` and `migrate` cannot see migrations that are pending in another developer's repository. | Repositories are independent by design; there is no shared ledger. | Coordinate schema work; preflight checks the live schema as it is. |
| An offline `migration-plan` report cannot see pending migrations in another repository or current database state. An `unlocked` folder only means no locking evidence was found in this checkout. | The report uses local files and receipt/attempt evidence only; there is no cross-repository ledger. | Coordinate schema work and use `migration-plan <folder> --live --env <env>` for the guarded live preflight. |
| `check-conflicts --local` does not enforce the schema-folder layout rule (flat folder in a multi-schema project). | `--local` loads no `.env`, so it does not know how many schemas are configured. It still refuses a `--schema` that differs from the folder and a batch that mixes schemas. | Run `check-conflicts --env dev` for the full check. |
| SQLcl prints `APEX_IMPORT_VERIFIED:<id>` even after an import it skipped (an unknown workspace in the descriptor, an unreadable `.apx`). | The marker only proves the app is visible after the import session. The SQL cannot tell a skipped import from a real one, and publish also requires SQLcl's own `Import successful.` line, so such a publish is still refused and nothing is claimed. | Nothing; read the refusal publish prints. |
| SQL that the analyzer cannot model (for example `ALTER SYSTEM`, `DBMS_*` calls, data changes) passes preflight when its folder declares checks. | Only the reviewed `checks.json` can vouch for it; preflight lists it as `REVIEW:`. | Review that SQL and its checks together before you migrate. |
| Live dependency preflight follows one direct owner-schema or PUBLIC synonym. An external target needs a direct `SELECT` grant to the owner or `PUBLIC`; an owner-owned selectable table, view or materialized view needs no separate grant. Synonym chains, database links and role-only grants are not resolved. | The bounded catalog capture records only local synonym targets and direct grant evidence needed to establish what the view owner can compile against. | Create a direct synonym to the target object and grant `SELECT` directly to the schema owner for external targets. Resolve chains and database links manually. |
| Live preflight refuses an owner catalog that keeps changing after the configured retry count. | Selected definitions must be compared to a stable object-name/type inventory; accepting a moving catalog could miss a real create or drop. | Wait for concurrent DDL or recompilation activity to settle and rerun `check-conflicts`; the refusal includes the last two inventory fingerprints. |
| DEV scenario SQL is trusted input, not sandboxed, and generated fixture names do not isolate indirect effects. | A scenario can commit, run DDL, or trigger autonomous/shared database work beyond its declared objects; DEV may also contain production-derived records. | Inspect the observed target, use synthetic run-tagged fixtures and review scenario effects. The runner requires a DEV profile and refuses production-looking identities, but cannot prove row provenance. See [dev-test.md](dev-test.md#limits-and-safe-use). |
| DEV test planning cannot guarantee future tablespace allocation from quota or free-space observations. | The schema owner may lack visibility, and available space can change between planning and execution. | DBA-wide visibility is advisory, not required. If fixture creation hits quota/allocation refusal, keep evidence, reduce the fixture if meaningful, or ask about space in the existing schema; do not automatically create another schema or replay an ambiguous write. |

## ORDS export

| Behaviour | Why it is kept | What to do |
| --- | --- | --- |
| `backup-ords` refuses a schema that owns an ORDS OAuth client. | SQLcl's `REST export schema` always includes OAuth clients (`p_include_oauth => TRUE`), and the template never exports OAuth clients, secrets or tokens. Removing them from the generated text would be a silent partial export. | Nothing; such a schema cannot be exported until SQLcl can leave OAuth clients out. |
| The ORDS export needs a login as the REST schema owner; a deployment account with `CURRENT_SCHEMA` is refused. | ORDS authorizes the actual session user, which `ALTER SESSION SET CURRENT_SCHEMA` does not change. | Save a connection that logs in as the REST schema owner. Do not enable REST for a deployment account. |
| ORDS is exported twice per schema. | The two exports must be identical; that is how a change during the export is detected without a lock. | Nothing. |
| A mismatch between the dictionary counts and the export's call counts fails the export, even when the export looks fine. | An export that silently holds less than the dictionary lists is worse than no export. | Run it again; if it repeats on a live system, report the entity and counts (the rules are `CALL_RULES` in `scripts/ords_export.py`). |
| The ORDS export was verified live only on ORDS 26.2.3 with SQLcl 26.2.2.0; other ORDS releases, non-REST-enabled and empty schemas, AutoREST objects and Windows were not. | The tests use a scripted fake SQLcl for everything else. | Run `scripts/team.sh doctor` and `backup-ords` against your DEV before relying on it; see [ords-export.md](ords-export.md#limitations-and-what-has-not-been-verified). |
| `backup-ords` lets the dictionary list more roles and privileges than the export holds. | The dictionary includes the roles and privileges that ship with ORDS, which ORDS does not export. | Nothing; an export with more of them than the dictionary lists is still refused. |

## SQLcl and rollout

| Behaviour | Why it is kept | What to do |
| --- | --- | --- |
| SQLcl trims whitespace-only lines in a plain script and treats a trailing hyphen as a continuation of the next line. | The SQLcl script reader normalizes these forms before Oracle sees the statement; a reviewed file cannot guarantee those exact bytes reach the database. | Do not deliver a PL/SQL package with intentional whitespace-only source lines through a `sql-script` rollout step. Assemble the source in a CLOB (for example, with `DBMS_LOB.APPEND`) and execute that CLOB from reviewed migration SQL. Avoid a trailing hyphen where a continuation is not intended. |
| SQLcl-backed rollout steps use a five-minute session timeout by default. | The shared SQLcl session runner keeps the existing 300-second default and records timeout evidence. A longer step can extend a production window or leave an apply outcome unknown. | Keep each step below about five minutes. Split a reviewed batch into independently verified steps; raise `MIGRATION_APPLY_TIMEOUT_SECONDS` only when the target operation and recovery plan justify it. |
| Exact APEXlang source-byte verification after an app import can differ across APEX patch levels, including trailing blank lines, comments and message ordering. | `verify_publish_state.py` intentionally requires the imported source to match local source bytes after documented projections; it cannot assume which patch-level serializer changes are harmless. | Prefer the same APEX patch level on source and target. On a mismatch, retain the publish evidence, compare a fresh target export and qualify each difference before retrying. Do not weaken the byte check based only on a patch-level guess. |

## Interrupts and signals

| Behaviour | Why it is kept | What to do |
| --- | --- | --- |
| `migrate` interrupted while a SQL step runs exits 2 ("may be partially applied"), not 130. | The result is unknown, not merely interrupted; 2 tells scripts not to treat it as a clean stop. | Reconcile as [migration-rules.md](migration-rules.md) says before retrying. |
| PowerShell 7 on Linux and macOS ignores cleanup on SIGTERM: `kill` ends `team.ps1`, while the Bash helper or SQLcl it started carries on, and its scratch folder stays. | PowerShell offers no script-level SIGTERM handler. Windows has no SIGTERM, and Linux users have `team.sh`, which hands its process to the helper. | Stop a PowerShell run with Ctrl-C, or signal its process group (`kill -TERM -- -<pgid>`); delete a left-over `scratch/` folder by hand. |
| A Ctrl-C that lands inside `Start-Process` itself, before it returns SQLcl to PowerShell, leaves that SQLcl unmanaged. | PowerShell cannot act on a process it has not been handed yet; the window is a few milliseconds, and SQLcl receives the same Ctrl-C. | Nothing. |
| `kill -9`, closing the terminal window, or a power cut stops any command without cleanup. | No program can clean up after being killed outright. | Treat a publish as an unverified import and a migration as possibly partial; see the publish and migration rules. |

## Internal scripts

| Behaviour | Why it is kept | What to do |
| --- | --- | --- |
| Helper scripts run directly (`scripts/publish_app.ps1`, `scripts/load_env.ps1`, `scripts/replace_mirror.ps1`, ...) can report a refusal differently from the wrappers. A PowerShell helper's refusal is an exception, so `pwsh` exits 1 and prints its error view. | The supported entry points are `scripts/team.sh` and `scripts/team.ps1`; they print the plain message and give the exit statuses listed in README. | Run commands through the wrappers. |
| `safe_rmtree` (Python scratch cleanup) does nothing for a path that is a symbolic link. | It only removes temporary directories the scripts themselves just created, never links, and `shutil.rmtree` never follows links inside a directory. | Nothing. |
