# Migration and schema comparison rules

This template stores each migration as one dated folder containing an ordered
set of SQL files. In a multi-schema project the folder is under
`migrations/<SCHEMA>/`; a migration folder changes only that schema. The files
and receipts belong to the local repository. Each developer has an independent
Git repository; repositories share Oracle state, not commits, migration
files, or pending work. The live schema is the source of truth for what
currently exists. No team metadata table, lock, roster, or database migration
ledger is used.

## Folder and file names

Use this layout for a multi-schema code profile:

```text
migrations/
└── DEMO/
    ├── 2026-09-28_create-customers-r002/
    │   ├── 001-add-status-column.sql
    │   ├── 002-update-customer-view.sql
    │   └── checks.json
    └── 2026-09-27_create-customers-r001/
        ├── 001-create-table.sql
        ├── 002-create-index.sql
        ├── 003-create-view.sql
        └── checks.json
```

Each folder is `migrations/<SCHEMA>/YYYY-MM-DD_<migration-name>-rNNN/`; do not
add a developer name. When `CODE_SCHEMA` contains exactly one schema, the
existing flat `migrations/YYYY-MM-DD_<migration-name>-rNNN/` layout remains
valid and the schema-folder layout is also accepted. When it contains two or
more schemas, the schema folder is required and a flat migration folder is
refused. With one schema, keep each migration family in one layout: `migrate`
and `check-conflicts` refuse a family that appears both flat and under
`migrations/<SCHEMA>/` for that schema, because both folders target it and
could apply the same revision twice. The same family under another schema's
folder targets a different schema and is allowed. The date is the folder creation date and stays the same when the
migration is promoted. The ISO date prefix sorts newer dates ahead when a file
browser is sorted descending; the name cannot set the browser's sort direction.
Folders created on the same date have a name-based tie-break, not an
intraday creation order.

The migration name uses lowercase kebab-case. Revisions begin at `r001` and
increase by one for each later folder with the same migration name within the
same schema. Each `(schema, migration name)` family has its own revision
sequence. For example, `create-customers-r001` and `create-customers-r002` in
one schema are separate, sequential migrations for the same intent. `r002`
contains the incremental follow-up, not a replacement copy of `r001`; its SQL
sequence starts again at `001`.

Use `scripts/team.sh revise <folder> [--reason TEXT]` to copy a folder into the
next revision in that same flat or `migrations/<SCHEMA>/` layout. It preserves
SQL filenames, sequence numbers, checks and existing README content, prepends
`Supersedes <old-folder>: <reason>` to the new README, and leaves the old folder
unchanged. The default reason is `follow-up revision`. Existing environment
receipts are not copied. The command refuses a source without an `-rNNN`
suffix, a revision at `r999`, a gap in the family history, or any newer family
revision. Its order hint lists the local family in ascending revision order;
include only folders that still need to be applied.

Each immediate SQL file is named `NNN-<step-name>.sql`; sequence numbers must
be unique and consecutive from `001`. The runner executes those files in
ascending numeric order in one migration session. When several folders are
selected, it executes them in the order supplied on the command line. The
descending folder display order is for browsing only and never determines
execution order. Review dependencies and pass folders in the required order.
Before the first write, a batch checks the first folder's preconditions; each
later folder's preconditions run just before that folder is applied, so they
may depend on what the earlier folders create. `check-conflicts` names the
folders whose preconditions it could not check yet. A later SQL step or folder
may also select from a synonym, stored unit or materialized view that an
earlier one creates. A
cross-schema change such as a grant or a synonym is two coordinated migrations,
one per schema.

SQL files hold only SQL: statements ended by `;` and PL/SQL blocks, types,
libraries, Java sources and MLE modules ended by a standalone `/`. SQLcl reads
some text as something other than part of the statement, so the validator
rejects it before SQLcl connects:

- a line holding only `/` or `.` inside a SQL statement (SQLcl ends the
  statement there and runs the next line as a command);
- a line holding only `/` inside a comment;
- a line starting with `@` inside a statement or block (SQLcl splices the named
  file into it, bytes that were never reviewed or hashed);
- a quoted identifier that spans lines;
- a string or quoted name standing between two statements (SQLcl reads it as a
  command, and the statement after it may not run);
- the comment opener `/*/` (SQLcl's parser fails on it and runs the comment's
  lines as commands; write `/* /` or `/**/`);
- a statement's first word glued to what follows (`DECLARE,`, `SELECT(`: SQLcl
  reads the first word up to the next space and runs the lines after it one by
  one; put a space after it).

Blank lines inside a statement are accepted: the apply session sets
`SQLBLANKLINES ON`, so an `UPDATE` with a blank line before its `WHERE` runs as
written.

Every folder requires a `checks.json` with read-only preconditions and
postconditions. These checks validate the expected starting state and verify
the committed result. The runner also performs structural catalog checks for
SQL forms it can analyze. Unsupported or data-changing operations need explicit
reviewed checks; incomplete verification blocks automated apply. When such an
operation has its checks, preflight passes but lists it as `REVIEW:`: the
analyzer cannot see what that SQL does, so only the checks stand for it.

Each check is one `SELECT` (or `WITH ... SELECT`) that returns the number `1`.
It may use ordinary query syntax, including parenthesized conditions and
subqueries, and these functions: `AVG`, `CAST`, `COALESCE`, `COUNT`, `LENGTH`,
`LOWER`, `MAX`, `MIN`, `NVL`, `REGEXP_LIKE`, `SUBSTR`, `SUM`, `TO_CHAR`,
`TO_NUMBER`, `UPPER`, and `SYS_CONTEXT` for `USERENV` `SESSION_USER` or
`CURRENT_SCHEMA`, `CHR`, `ORA_HASH`, `STANDARD_HASH`, `DECODE`, `NULLIF`,
`INSTR`, `REPLACE`, `TRIM`, `LTRIM`, `RTRIM`, `LENGTHB`, `LPAD`, `RPAD`, and
`LISTAGG`. Its only bind is `:target_schema`. Non-ASCII text belongs
inside a string literal, a quoted name or a comment. A call to any other
function (yours or a built-in not listed) is refused when it is written with
parentheses, so is a sequence `NEXTVAL`/`CURRVAL`, `FOR UPDATE`, a database
link, or any statement that writes; express other tests with `CASE` and the
listed functions. The validator reads the text, not the database, so a stored
function named without parentheses (`my_func`, `my_pkg.is_ready`) looks like a
column to it and is not refused. The check session is read-only and cannot
commit inside PL/SQL (`ALTER SESSION DISABLE COMMIT IN PROCEDURE`), so a
function that writes, whether directly, through an autonomous transaction or
through DDL, fails the check with `ORA-00034` instead of writing. Do not call
stored functions in a check anyway: one that does something that is not
transactional, such as writing a file or sending a request, is not stopped.

The additional allowed functions have bounded, argument-only behavior:

| Function | Why its use is allowed in a check |
| --- | --- |
| `CHR` | Maps an integer code to a character without reading or changing database state. |
| `ORA_HASH` | Computes a repeatable hash when the expression, seed and bucket limit are fixed. |
| `STANDARD_HASH` | Computes a digest from its input and selected algorithm. |
| `DECODE` | Selects an output by equality comparison. |
| `NULLIF` | Returns null or its first argument based only on equality. |
| `INSTR` | Returns a matching position in its input text. |
| `REPLACE` | Substitutes text using its input arguments. |
| `TRIM` | Removes edge characters from its input text. |
| `LTRIM` | Removes leading characters from its input text. |
| `RTRIM` | Removes trailing characters from its input text. |
| `LENGTHB` | Measures input byte length under the database character set. |
| `LPAD` | Adds left padding using its input arguments. |
| `RPAD` | Adds right padding using its input arguments. |
| `LISTAGG` | Aggregates input text in declared order; use a unique order key for repeatability. |

`ORA_HASH` and `STANDARD_HASH` are fingerprints, not collision-proof source
equality checks. Include a reviewed row count and line number in source checks,
and validate the expected values on each database release before relying on
them. Use exact source comparison where hash collisions are unacceptable.

Check SQL is encoded and delivered in bounded sessions. The generated driver
size defaults to `MIGRATION_CHECK_BATCH_BYTES=2097152` (2 MiB); a single check
over the configured budget is refused before SQLcl starts. Each session keeps
the read-only transaction and disabled-commit guards, and the runner checks
every session's observed database identity before accepting the merged result.
`MIGRATION_APPLY_TIMEOUT_SECONDS` and `MIGRATION_CHECK_TIMEOUT_SECONDS` both
default to 300 seconds. Set either to another positive finite number of seconds
when a reviewed operation needs it. A timeout leaves verification incomplete;
an apply timeout may have committed DDL, so reconcile the retained evidence
before retrying. The timeout and batch-limit values are optional `.env` keys.
The optional `MIGRATION_PREFLIGHT_INVENTORY_RETRIES` key accepts a
non-negative integer and controls inventory-change retries independently of
the SQLcl timeout.

SQLcl reports a PL/SQL or view compilation error as a warning and carries on,
so the apply session ends with its own check. Every package, package body,
type, type body, procedure, function, trigger, view, library, Java source or
MLE module that the migration's own `CREATE` or `ALTER ... COMPILE` statements
name is looked up in `ALL_OBJECTS` and `ALL_ERRORS`. One with errors, or one
the session cannot find or see, fails the apply with `ORA-20986: Migration left
objects with compilation errors or that it cannot see`. A name without a schema
prefix belongs to the session's current schema, including after an
`ALTER SESSION SET CURRENT_SCHEMA` earlier in the migration; a unit the
migration drops again is not checked. A plain `ALTER PACKAGE` or `ALTER TYPE
... COMPILE` also checks the body when one exists. Objects the migration does
not name, including a teammate's unrelated work, are never checked. The DDL
has already committed by then; no receipt is written, and the next revision
fixes the object. Units created through dynamic SQL (`EXECUTE IMMEDIATE`) are
not named in the file; cover those with an explicit postcondition, for example
a count of `INVALID` objects in `ALL_OBJECTS`.

## Immutability and status receipts

Once a migration has been applied or a write attempt may have begun, keep its
SQL bytes, names, order, and `checks.json` unchanged. A correction or recovery
belongs in the next revision folder. A failed or ambiguous attempt may have
left Oracle DDL committed, so inspect the live schema before deciding how to
recover or retry. An interrupted `migrate` says which case it is: interrupted
while a SQL step runs, it prints "was interrupted and may be partially applied"
and exits 2, because the result is unknown; interrupted anywhere else it exits
130 and says whether a write was attempted ("no writes were attempted", or
"interrupted after a write was attempted; stop and reconcile").

Every `migrate` that reaches the apply boundary leaves its record in
`scratch/migration-attempt-*` (SQL, SQLcl log and outcome). For each folder, the
runner writes `write-attempted` before starting SQLcl. Before each payload file
it prints `MIGRATION_PAYLOAD_STARTED:<filename>`; successful completion prints
`MIGRATION_APPLY_COMPLETED`.

A failed apply becomes `apply-not-started` and is not locked only when the
retained SQLcl output proves a pre-payload refusal: a migration identity guard
error (`ORA-20980` through `ORA-20985` before `MIGRATION_IDENTITY_VERIFIED`,
or `ORA-20987` with both `MIGRATION_IDENTITY_VERIFIED` and
`MIGRATION_IDENTITY_GUARD_REFUSED`), a recognized connection error before
the first `MIGRATION_PAYLOAD_STARTED` marker (`ORA-01017`,
`ORA-12154`, `ORA-12514`, `ORA-12537`, `ORA-12541`, `ORA-12545`, `ORA-12547`,
`ORA-12560`, `ORA-12637`, or `SP2-0640`), or a local SQLcl start failure. The
output must not contain `MIGRATION_PAYLOAD_STARTED` or
`MIGRATION_APPLY_COMPLETED`. The record sets `writeAttempted` to false and the
folder can be retried or revised.

Any payload-start marker, a missing or unreadable log, an unrecognized error,
an interrupt, or a timeout remains locked as `apply-failed-or-unknown`.
`write-attempted`, `committed-unverified`, `committed-verification-failed`,
`committed-receipt-failed`, `committed-source-or-payload-changed`, and
`verified` attempt/receipt states are locked too. Only `frozen` and
`apply-not-started` records with `writeAttempted: false` are unlocked;
inconsistent or unknown evidence does not unlock a folder. A
timeout after a payload marker stays locked even when SQLcl printed no ORA
error: this covers the DEV26 1,856-statement file cut off after five minutes.
ORA errors after a payload marker also stay locked because earlier statements
may have run. A verified receipt locks the folder as well. Use
`scripts/team.sh revise --check <folder>` to see the local attempt and receipt
states; exit 0 means unlocked, 1 means locked, and 2 means evidence is unknown
or unreadable. An attempt directory without `run-manifest.json` is incomplete
evidence and returns 2 because its target folder cannot be established.

This rule is intentionally narrow. It recognizes the identity refusal and
connection/start errors above only when no payload marker was printed; a
recognized connection error after the identity marker but before the first
payload marker still qualifies. SQLcl does not provide a durable per-statement
execution ledger, so a truncated, missing, or ambiguous output cannot prove
that the database was untouched and stays locked. A connection loss after
SQLcl prints a payload marker is also ambiguous and stays locked, even if the
first statement may not have reached Oracle. The local check sees only this
checkout's receipts and ignored `scratch/` evidence; it does not see another
developer's repository or prove current live schema state. `scratch/` is
ignored by Git and is not shared with teammates.

The runner creates `status.dev.json`, `status.staging.json`, or
`status.prod.json` only after SQLcl confirms the apply session completed and a
fresh connection verifies the target identity and postconditions. It records
the exact SQL and checks hashes, target identity, and verification evidence.
These files are evidence from this checkout; they are not a shared ledger.
Never create a planned, pending, failed, or aspirational status file, and do
not treat a receipt by itself as proof of today's live state.

## Conflict checks and the independent-repository limit

Run the conflict checker on the folders you intend to apply:

```bash
scripts/team.sh check-conflicts \
  migrations/2026-09-27_create-customers-r001 --env dev
scripts/team.sh check-conflicts \
  migrations/2026-09-27_create-customers-r001 --local
```

`--local` checks the selected files and their ordered effects without a
database connection. Live mode additionally checks those effects against the
selected environment's observed catalog. `migrate` repeats the live
preconditions before applying. The checker handles common object namespace
collisions, table columns, and supported dependencies; it reports when an SQL
form needs explicit checks or cannot be analyzed safely.

For unqualified view dependencies, live preflight captures private synonyms in
the selected owner and PUBLIC synonyms, plus direct `SELECT` grants to that
owner or `PUBLIC`. An owner synonym takes precedence over a PUBLIC synonym. A
reference through either synonym is satisfied only when its direct target is a
live table, view or materialized view, an earlier-staged table or view, or a
matching direct `SELECT` grant proves the owner can read the external target.
A missing target, missing grant, synonym chain or database-link target remains
a missing prerequisite. These catalog reads are read-only; local-only analysis
cannot establish synonym or grant reachability.

Live preflight compares the owner inventory by object owner, object name,
subobject name and type. Status, `LAST_DDL_TIME`, object IDs and other volatile
attributes that can change without an object or subobject name/type change are
ignored. If an object or subobject name or type changes between discovery and
selected-definition capture, preflight retries the full inventory/snapshot pair up to
`MIGRATION_PREFLIGHT_INVENTORY_RETRIES` times after the first attempt. The
default is `3` retries; `0` disables them. After the retries are exhausted it
returns `LIVE_PREFLIGHT_UNAVAILABLE` with SHA-256 fingerprints for both
inventories; wait for catalog activity to settle and rerun the check.

A table, view or sequence name that is already taken is a conflict, whether the
database holds it or an earlier selected folder creates it. The one exception is
a `CREATE OR REPLACE VIEW` that replaces a view, in the database or created by
an earlier folder of the same batch, and whose folder declares a precondition
for the expected prior view; the report lists it as needing review.

This is selected-batch analysis plus live-state preflight, not discovery of
other developers' pending files. Because independent repositories do not share
migration files, two developers can both pass while the shared catalog is
still empty. When one applies, the other's later live preflight should detect
the resulting object. A concurrent change after preflight can still race the
apply. The database's own DDL checks remain the final defense, and failures
that may have partially committed require live reconciliation.

## Environment targets

Apply with an explicit environment:

```bash
scripts/team.sh migrate \
  migrations/2026-09-27_create-customers-r001 --env dev
scripts/team.sh migrate \
  migrations/2026-09-27_create-customers-r001 --env staging
scripts/team.sh migrate \
  migrations/2026-09-27_create-customers-r001 --env prod
```

DEV uses `CODE_SQLCL_CONNECTION`, `CODE_EXPECTED_USER`, and `CODE_SCHEMA`.
Staging and production reuse `STAGING_SQLCL_CONNECTION` /
`STAGING_EXPECTED_USER` and `PROD_SQLCL_CONNECTION` / `PROD_EXPECTED_USER`,
with explicit `STAGING_SCHEMA` and `PROD_SCHEMA`. Set the schema separately
because the owner can differ between environments even when the saved
connection and deployment roles are already configured. Do not assume staging
or production has the same schema name as DEV, and do not fall back to DEV when
a target is incomplete. The SQLcl login user may differ from the schema owner.

Staging and production applies show the resolved target and require an
interactive confirmation. The runner verifies the observed database identity
and current schema before writing and verifies the committed result afterward.
The apply session compares its database name, unique name, service, container,
edition and version with the preflight observation before it runs the first
SQL file (`ORA-20987`), and every precondition and postcondition session
reports its identity too, so results observed on a different database are
refused. Receipts are written only for verified applies.

A connection name, database name, unique name or service name that looks like
production (`prod`, `prd`, `production` or `live` as a word, `PRODDB`,
`ERPPROD`, `erpprod.example.com`) is refused unless the selected target is
production. Pre-production names such as `PREPROD`, `NONPROD`, `pre-prod` and
`non_prd` do not count as production. This is a naming heuristic, not a guarantee: name non-production
databases so they do not match it, and rely on the expected-user check and the
team's review for the rest.

## Comparing selected live objects

Compare a list of objects or prefixes across two live environments:

```bash
scripts/team.sh compare-schema --from dev --to staging \
  --object CUSTOMERS --object ORDERS
scripts/team.sh compare-schema --from staging --to prod \
  --pattern 'HR_*' --pattern 'GL_*'
scripts/team.sh compare-schema --env prod --pattern 'HR_*'
```

The short form compares DEV with the selected `--env`. Repeat `--object` for
exact object names and `--pattern` for uppercase names using `*` as the only
wildcard. `_` is literal, so `HR_*` does not select `HRX_EMPLOYEES`. Selection
is the union of objects found in either catalog. Comparison captures catalog
inventory, table columns, views, sequences, and normalized metadata DDL for
selected objects. It reports missing target objects/columns, changed
definitions, target-only objects, and incomplete catalog visibility. It does not
compare table or column comments, grants, storage settings, or data.

This is a live schema drift check, not reliable migration-file attribution.
Local `status.<env>.json` receipts can help an operator identify migrations to
review, but each repository sees only its own receipts. Equivalent resulting
DDL can come from different migration files, and an out-of-band manual change
can mimic a migration. Conversely, normalization intentionally excludes some
environment-specific metadata. Treat the output as a coarse comparison of
selected current schema state, then review the implicated SQL and receipts.

## Read-only verification

Use `scripts/team.sh verify <folder> [...] --env <env>` to run declared checks
without applying migration files. `--phase pre`, `--phase post`, or
`--phase both` selects the checks; `--only-failed` omits passing checks from
the display, `--format json` emits a machine-readable report, and `--jobs N`
limits parallel read-only check sessions. Each session is bounded by the
configured driver size and timeout. Exit status 1 means one or more checks
returned false; status 2 means the target or verification could not be
confirmed. Failed reports retain private diagnostics under `scratch/`.

## Rehearsal

Use `migrate --rehearse` to try data changes on the selected real target and
roll them back without writing a receipt or a migration write-attempt marker:

```bash
scripts/team.sh migrate \
  migrations/2026-09-27_seed-customers-r001 \
  migrations/2026-09-28_assign-customers-r001 \
  --env dev --rehearse --report scratch/customer-rehearsal.json
```

The command freezes the selected files, verifies the target identity, and
requires staging/production confirmation as the normal apply does. Before the
data session it sets `AUTOCOMMIT OFF` and verifies SQLcl reports it off. If
SQLcl cannot confirm that state, rehearsal stops before any migration file is
run. The data session also uses `WHENEVER SQLERROR EXIT FAILURE ROLLBACK`, the
migration identity guard, and `ALTER SESSION DISABLE COMMIT IN PROCEDURE`.

The existing `analyze_batch` analyzer classifies every file. A file runs only
when all its statements are `INSERT`, `UPDATE`, `DELETE`, or `MERGE`, and its
folder declares both preconditions and postconditions. A file with DDL,
`TRUNCATE`, privilege changes, PL/SQL, an unrecognized statement, or a mixture
of data changes and any other statement is skipped in full and reported as
`not rehearsable` with the analyzer's reason. The command never executes the
skipped file. This limit keeps implicit-commit and unmodeled SQL outside the
rollback claim.

For each folder, rehearsal evaluates its preconditions, runs its eligible
files in input order, then evaluates its postconditions. These check queries
are validated by the same `SAFE_FUNCTIONS` check validator as ordinary
migration checks, but run as SELECTs inside the rehearsal SQLcl session without
starting a separate read-only transaction. Later folders therefore see rows
from earlier folders in the same rehearsal. SQLcl feedback is associated with
each statement where it prints a row count; otherwise that statement's
`rowsAffected` is null.

After all selected folders, the driver issues `ROLLBACK`. The rollback proof
includes the preconditions re-run after `ROLLBACK`: each folder's own checks,
evaluated in that same session. When the data session exits early on an SQL error or failed
precondition, the command uses fresh read-only check sessions to re-run those
preconditions after SQLcl's rollback. The report marks rollback proof true only
when the preconditions are complete and still true.
An SQL error still returns 2 even when the fresh preconditions prove rollback;
inspect the error and report before deciding what to change.

`--report <file>` writes schema-version 1 JSON with each folder's files,
statements, rows affected, postcondition status, and rollback proof. It is
valid only with `--rehearse`. Exit 0 means every selected file was rehearsable,
postconditions passed, and rollback was proven. Exit 1 means a check was false
or at least one file was skipped as not rehearsable. Exit 2 means SQLcl,
identity, configuration, check evaluation, report writing, or rollback proof
could not complete. Rehearsal evidence is kept under
`scratch/migration-rehearsal-*` when SQLcl fails; successful runs remove it.

## Rollout

`scripts/team.sh rollout <manifest.json> --env <env>` executes a reviewed
release as an ordered manifest. The [example manifest](rollout-manifest.example.json)
shows each supported step type. Replace the example paths, aliases, schemas
and application ID with project-owned files and descriptors before use.

The manifest is UTF-8 JSON with no duplicate keys. Its root contains exactly
`schemaVersion` (integer `1`) and a nonempty `steps` array. Paths are relative
to the repository root, use forward slashes, and may not contain `.`/`..`,
symbolic links or generated `scratch/` state. Supported step types are:

| Type | Required properties | Behavior |
| --- | --- | --- |
| `migrate` | `folders` | Runs a normal migration batch with its preflight and receipts. |
| `verify` | `folders`, `phase` (`pre`, `post`, or `both`) | Runs declared read-only migration checks. |
| `sql-script` | `file`, `connection`, `expectedUser`, `schema` | Runs a reviewed DBA SQL file after checking the session and database identity. |
| `ords-import` | `file`, `connection`, `expectedUser`, `schema` | Validates a generated ORDS export and uses the guarded SQL script path. |
| `app-deploy` | `appId` | Runs the existing deployment command and explicit environment descriptor; staging and production only. |
| `pause` | `message` | Prints the message and waits for Enter before continuing. |

Every input is hashed before execution and checked again around each step. A
staging or production run has one manifest-level confirmation listing the
manifest, destinations and input hashes; there is no confirmation bypass. DEV
uses the normal DEV identity and migration guards. `--dry-run` validates
inputs and writes reports without executing steps. JSON and Markdown reports
include step status, timing, hashes and evidence paths. Successful receipts
are local recovery evidence under `scratch/rollout-receipts/`; resuming with
`--from-step N` requires matching receipts for every earlier step. Inspect
target state before resuming after an ambiguous write. Reports may not overlap
rollout inputs, receipts or recovery evidence.
