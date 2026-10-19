# APEX project template for teams

This template supports APEX 26.1+ applications authored as APEXlang. It uses
plain Git source, explicit deployment JSON, and dated, ordered SQL migration
folders. No custom team metadata schema or database lock tables are required.

Projects created from this template use one Git repository per developer.
Those repositories do not share commits or a remote; developers coordinate
through the shared development database and APEX Builder workspace. Branches
separate file changes only and do not isolate a shared APEX application.

## Start here

| I want to… | Read |
| --- | --- |
| set everything up for the first time | [Getting started](docs/GETTING_STARTED.md) |
| do a specific task, step by step | [Examples](docs/EXAMPLES.md) |
| understand an error message | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| look up a command | [Command reference](#command-reference) |
| inspect migration folders before selecting an order | [Migration planning](docs/migration-planning.md) |
| compare full environment catalogs or generate a baseline | [Environment comparison](docs/compare-env.md), [Baseline generation](docs/baseline.md) |
| see the 26.1 backport qualification | [APEX 26.1 qualification](docs/apex-26.1-qualification.md) |
| know exactly when publish or migrate refuses | [publish-rules](docs/publish-rules.md), [migration-rules](docs/migration-rules.md) |
| know which limits are deliberate | [Known limitations](docs/known-limitations.md) |
| see what an AI assistant can do here | [Skills and agent support](#skills-and-agent-support) |

After cloning this template into your own project, complete the
[post-clone cleanup](docs/GETTING_STARTED.md#post-clone-cleanup). Downstream
projects remove inherited template-maintenance tests, GitHub workflows and
Dependabot; the original template keeps them for its own validation. Retain
project-specific tests and the operational scripts, `.env`, manifest and lock.

## What you get

| Feature | What it does |
| --- | --- |
| APEX apps as text in Git | `export` copies a live app into APEXlang files you can review, diff and commit. |
| Two ways to work | **Builder-first** (change it in APEX, export it) or **file-first** (edit the files, publish them). |
| Safe publish | Refuses to overwrite newer Builder work, stamps who published and when, then re-exports the app and checks it byte for byte against your files. |
| SQL migrations | Dated folders of numbered SQL plus `checks.json`; a live check for conflicts before applying; a verified receipt after. |
| DEV test runner | Read-only planning and explicit schema-owner fixture runs with durable reports and retained results; see [DEV test runner](docs/dev-test.md). |
| Environment baselines | Read-only capture and granular or optionally bundled structure, grant and exact-source migration generation, with separate optional reference data. |
| Schema comparison | Read-only comparison of selected tables, views and code between DEV, staging and production. |
| Several schemas per workspace | Comma-separated lists in `.env` and `--schema`; apps, database copies and migrations are kept per schema. |
| Staging and production | Per-app descriptors, an explicit `[y/N]` confirmation, and `--manual` to print a runbook for a DBA. |
| Read-only database copy | `backup-db` mirrors tables, views, packages, procedures, functions, triggers and synonyms (structure only, never data). `backup-ords` adds an optional, read-only export of a schema's ORDS (REST) definition. |
| Safety built in | Every connection is identity-checked, production-looking names are caught, production is read-only, file installs are all-or-nothing, and your uncommitted work is never overwritten. |
| Template upgrades | `upgrade-template` updates the template's own files and never touches your apps, migrations, database copy or `.env`. |
| Knowledge graph | Optional Graphify index that links each app's pages, regions and processes to the tables and packages they use. |
| AI-assistant support | Repository rules, 11 skills plus optional workflow packs, SQLcl MCP guidance and a Chrome DevTools daemon for assistants such as Claude Code and Codex. |
| Bash and PowerShell | `scripts/team.sh` and `scripts/team.ps1` expose the same commands. |

## Skills and agent support

AI coding assistants read [AGENTS.md](AGENTS.md) (Claude Code loads it through
`CLAUDE.md`) for the rules and load a skill on their own when a task matches
its description. The same 11 skills for APEX and project setup are listed in `.agents/skills/` (for agents
that follow the `AGENTS.md` convention) and `.claude/skills/` (for Claude Code).
Three Claude Code entries (`chrome-devtools-mcp`, `safeguarding-apexlang-text-messages`
and `sqlcl-mcp-r0`) are short pointers to the full `.agents/skills/` copy.
You do not have to call them by name.

Agents also load a conversation style at the start of each conversation: set `AGENT_STYLE` in
`.env` (`standard`, `concise`, `teaching` or `asharif-style`). Your own preferences accumulate in
`.agents/styles/personal.md`; see [.agents/styles/README.md](.agents/styles/README.md).

**APEX and database skills**

| Skill | Use it when |
| --- | --- |
| `initialize-project` | Setting up a new copy: `/init` asks a few questions, checks your tools and writes `.env`. It never handles passwords. |
| `apex-background` | Writing or debugging PL/SQL in automations, workflow activities, task actions or background chains. |
| `apex-session-context` | SQL or PL/SQL outside a page request reads task or workflow views or calls workflow APIs (SQLcl, schedulers). |
| `apex-workflow-lifecycle` | Importing or moving an app that has live workflow or task instances, or diagnosing a missing schedule. |
| `apexlang-export-debugging` | An APEXlang export fails with `ORA-01403` in `WWV_META_META_DATA`. |
| `optimizing-apex-task-inboxes` | Task inboxes are slow from repeated task API or view calls. |
| `safeguarding-apexlang-text-messages` | Localizing or repairing `textMessages` without breaking substitutions or tokens. |
| `sqlcl-mcp-r0` | An assistant operates SQLcl through MCP at restriction level 0. |
| `sqlcl-script-path-debugging` | Nested SQLcl scripts load the wrong file, or relative `SPOOL` and include paths misbehave. |
| `chrome-devtools-mcp` | Inspecting or driving your running web app in Chrome through the project's persistent DevTools daemon. |
| `install-uc-apx` | Installing or verifying the optional `uc-apx` command-line tool when `INSTALL_UC_APX=true`. |

**Optional workflow packs:** choose Superpowers, Matt Pocock's skills, both, or
neither during `/init` or later. New projects default to neither. Installations
are local and ignored; pinned commits and content hashes are recorded.

```bash
scripts/team.sh skills setup both --primary superpowers
scripts/team.sh skills status
scripts/team.sh skills setup none
```

With both installed, use one primary workflow per task. This setting does not
disable user-level skills or app plugins. See [workflow skill setup](docs/workflow-skills.md)
for all choices, Matt's follow-up setup, upgrades and recovery.

Rules and workflows that apply to everyone, human or assistant, live in
`.agents/rules/` (`agent-safety.md`, `graphify.md`) and `.agents/workflows/`
(`team-flow.md`, `graphify.md`, `uc-apx.md`). Put your project's own
instructions in `AGENTS.project.md`, `.agents/rules/project.md` and
`PROJECT.md`; template upgrades never overwrite those.

## Quickstart

New here? Follow [Getting started](docs/GETTING_STARTED.md): it walks through
everything below with the output you should see. You need SQLcl 26.1 or newer,
Git, Python 3.10 or newer, Bash 4.3 or newer, and an Oracle database with
APEX 26.1 or newer. To practice locally, the
[United Codes `uc-local-apex-dev`](https://github.com/United-Codes/uc-local-apex-dev)
containers give you one.
Live `compare-env` and `baseline` commands require SQLcl 26.3.0.0 or newer;
offline help and ORDS filtering do not start SQLcl.

Copy the example configuration, set `DEVELOPER_NAME` to your uppercase name
(for example `ASHARIF`), adjust SQLcl saved connection names and expected
users, then check the DEV connection:

```bash
cp .env.example .env
scripts/team.sh doctor
```

The example uses `docker-demo` / `DEMO`. Table, code, and APEX settings can
share that connection. Staging and production app-deployment profiles are
optional connection/user pairs; migrations and schema comparison also require
an explicit target schema. Store credentials in SQLcl's secure connection
store, never in `.env` or Git. After validating your configuration, review
and keep the credential-free root `.env` in your own downstream Git repository.
It contains literal settings and saved connection names only; nested `.env`
files and `.env.*` variants remain ignored. The template ships `.env.example`
and does not create or commit a configured `.env` for you.

On Windows, use the PowerShell wrapper:

```powershell
Copy-Item .env.example .env
pwsh -File scripts/team.ps1 doctor
```

`powershell.exe` (Windows PowerShell 5.1) works the same way. Windows also
needs Git for Windows (the migration, comparison and deployment helpers run in
its Bash), Python 3.10 or newer, and SQLcl on `PATH` for database operations.
Offline `migration-plan` needs no SQLcl. Four things trip people up there:

- **Script policy.** Windows PowerShell 5.1 on a client Windows starts with the
  `Restricted` policy and refuses to run any `.ps1`. Allow your own account to
  run local scripts with `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
  A copy downloaded as a ZIP carries a "from the internet" mark that
  `RemoteSigned` still blocks; clone with Git, or run
  `Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File` once.
- **Python.** The Bash helpers behind `migration-plan`, `check-conflicts`, `migrate`,
  `compare-schema` and `deploy` call `python3`, which a python.org or winget
  install does not provide (the Microsoft Store `python3.exe` is a stub when
  Python came from elsewhere). `team.ps1` finds a working Python (`python3`,
  `python`, then `py -3`) and gives Git Bash a `python3` for that run, so there
  is nothing to set up. If you run `scripts/team.sh` straight from Git Bash and
  see `python3: command not found`, create one once and open a new Git Bash
  window: `mkdir -p ~/bin && printf '#!/usr/bin/env bash\nexec py -3 "$@"\n' > ~/bin/python3 && chmod +x ~/bin/python3`.
- **File encoding.** Migration SQL and `checks.json` must be UTF-8 without a
  byte-order mark and with LF line endings, and are refused otherwise. A
  deployment descriptor must be UTF-8 without a byte-order mark (a BOM is
  refused; CRLF is accepted). `Set-Content -Encoding UTF8` and `Out-File` in
  Windows PowerShell 5.1 write a BOM, UTF-16 or CRLF. Create the files in an
  editor set to UTF-8 and LF, or with
  `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`.
- **Checkout path.** Prefer a folder name without `[` and `]`. PowerShell reads
  them as wildcards in many cmdlets and Git Bash does not convert such a path
  for native programs; the scripts work around both, but your own commands in
  that folder may not (`Set-Location "C:\work [1]"` fails; use `-LiteralPath`).

`team.ps1` accepts a migration folder as `migrations\2026-10-02_name-r001`,
`.\migrations\2026-10-02_name-r001\` or an absolute path inside the checkout.

## ORDS metadata (optional)

`backup-ords` keeps a schema's REST modules, templates, handlers, parameters,
roles and privileges in Git as `database/<SCHEMA>/ords/schema.sql`. It is off
until all three `ORDS_*` keys are set, so existing projects change nothing:

```dotenv
ORDS_SCHEMA=REST_API
ORDS_SQLCL_CONNECTION=dev-rest
ORDS_EXPECTED_USER=REST_API
```

```bash
scripts/team.sh backup-ords                      # every ORDS schema
scripts/team.sh backup-ords --schema REST_API    # one
scripts/team.sh backup-db                        # tables, code and ORDS together
```

The saved connection must log in **as the REST schema owner**: the session user
must equal `ORDS_SCHEMA` and `ORDS_EXPECTED_USER` (and `.env` loading refuses
two that differ). `ALTER SESSION SET
CURRENT_SCHEMA` does not count, because ORDS authorizes the actual login user.
It needs SQLcl 26.1 or newer and an ORDS release with the schema export API
(Oracle documents it from ORDS 25.1).

It only exports. It never enables REST, imports the generated SQL, changes ORDS
configuration, creates metadata, grants privileges or commits. OAuth clients,
client secrets, tokens and credentials are never exported: a schema that owns an
OAuth client is refused, because SQLcl's schema export always includes them.
Application data is not exported either.

An export is installed only after it passes checks that do not rely on SQLcl's
exit status: identity, completion, a before-and-after inventory from the ORDS
dictionary views, the call counts in the script, and a second identical export.
A verified empty schema is a valid result; an unavailable inventory is a failure.
The previous mirror is kept on any failure or interruption, and `backup-ords`
leaves the table and code mirrors alone. Details, every message and what has not
been verified: [docs/ords-export.md](docs/ords-export.md).

## Application files and deployment descriptors

Use the numeric APEX application ID as the stable source directory key. The
standard layout is:

```text
apps/DEMO/100/
├── application.apx
├── .apex/
└── deployments/
    ├── dev.json
    ├── staging.json
    └── prod.json
```

`apps/templates/deployments/` contains example JSON descriptors. Copy the
needed descriptors into each app and set its workspace name, numeric app ID,
and target parsing schema. Keep `dev.json` aligned with the configured DEV
profile. A staging descriptor is needed only when the project uses staging.

## Several schemas in one workspace

The schema, SQLcl connection, and expected-user values in each profile are
comma-separated lists aligned by position. For example, this DEV setup uses
two schemas in each profile:

```dotenv
TABLES_SCHEMA=APP_ONE,APP_TWO
TABLES_SQLCL_CONNECTION=dev_app_one,dev_app_two
TABLES_EXPECTED_USER=APP_ONE,APP_TWO

CODE_SCHEMA=APP_ONE,APP_TWO
CODE_SQLCL_CONNECTION=dev_app_one,dev_app_two
CODE_EXPECTED_USER=APP_ONE,APP_TWO

APEX_PARSING_SCHEMA=APP_ONE,APP_TWO
APEX_SQLCL_CONNECTION=dev_app_one,dev_app_two
APEX_EXPECTED_USER=APP_ONE,APP_TWO
APEX_APP_ID=117,301
```

All three values in each profile must have the same number of entries, and a
schema may appear only once in a profile. A single value keeps the existing
single-schema behavior. Prefix filters apply to every schema in their profile.
When staging or production profiles are configured, a DEV schema maps to the
same name in those schema lists. One exception keeps today's behavior: a
project with a single DEV schema may name its staging or production schema
differently, and that mapping applies only to the project's one configured DEV
schema. An unlisted schema is never mapped to a target.

Pass `--schema <NAME>` to narrow a command to one schema. `doctor` and
`backup-db` check or mirror all configured schemas by default.

| Command | Multi-schema behavior |
| --- | --- |
| `doctor` | Checks every distinct `(connection, expected user, schema)` across the three profiles, and every ORDS target when that optional profile exists, with one read-only SQLcl identity check each. It reports each schema and fails if any check fails. `--schema` narrows it. |
| `export <id>` | Reads the app's parsing schema from `APEX_APPLICATIONS` using the first `APEX_SQLCL_CONNECTION` entry, requires that schema in `APEX_PARSING_SCHEMA`, then reconnects with that schema's own connection and writes `apps/<SCHEMA>/<id>/`. `team.sh export` takes one ID. `scripts/export_apps.sh` with no argument resolves each configured app ID separately and installs all exports in one all-or-nothing mirror replacement. |
| `backup-db` | Runs the tables scope for each tables schema and the code scope for each code schema, plus the ORDS scope for each ORDS schema when the optional ORDS profile exists. Each has a staging directory, a completeness check, and a dirty-mirror check. Nothing is installed until every schema verifies; one mirror replacement installs them all. `--schema` narrows the run. |
| `backup-ords` | Exports each ORDS schema (`ORDS_SCHEMA`, optional) to `database/<SCHEMA>/ords/schema.sql` and replaces only that folder. `--schema` narrows the run; an ORDS-only schema is selectable. |
| `publish <id>` | Requires the app folder, descriptor, and live app parsing schema to agree and be listed, then uses that schema's connection. The drift guard, version stamp, and byte-equality verification remain unchanged. |
| `deploy <id> --env staging\|prod` | The descriptor's `parsingSchema` selects the same-named staging or production entry. Confirmation shows the schema and connection. |
| `migrate`, `check-conflicts` | Uses `migrations/<SCHEMA>/YYYY-MM-DD_<name>-rNNN/`; the folder selects the target entry. Scans, revision ordering, and receipts are scoped to one schema, and one invocation cannot mix schemas. |
| `compare-schema` | Requires `--schema` when more than one schema is configured and compares that schema across the selected environments. |

When `CODE_SCHEMA` has one schema, the existing flat
`migrations/YYYY-MM-DD_<name>-rNNN/` layout remains valid and the
`migrations/<SCHEMA>/` layout is also accepted. With two or more code schemas,
the schema folder is required and a flat folder is refused. One migration
changes one schema. A cross-schema change such as a grant or synonym is two
coordinated migrations, one per schema. Private synonyms are mirrored under
`database/<SCHEMA>/synonyms/` with the code objects.

Limits:

- Position-aligned lists rely on order; the loader cannot detect values that
  were swapped consistently across a profile.
- Schemas sharing one SQLcl connection share its privileges. Identity checks
  confirm the session user, not that it can reach only one schema.
- `--local` conflict checks load no `.env`, so they cannot enforce the
  schema-folder layout rule. They still refuse a `--schema` that differs from
  the folder's schema and a batch that mixes schemas.
- `publish --force` skips the drift check, but still requires schema agreement
  between the app folder, descriptor, and live app.

## Builder-first workflow

Make and save the change in shared APEX Builder, then export that app's source:

```bash
scripts/team.sh export 100
git status --short --untracked-files=all -- apps/DEMO/100/
git diff -- apps/DEMO/100/
```

Review the APEXlang changes before committing. This route captures current
Builder state; it does not import the app back into Builder. The exporter
refuses to overwrite a dirty local source directory. It first exports into
`scratch/`, checks the SQLcl result and Builder revision, then replaces the
local source mirror while preserving its authored deployment descriptors.

## File-first APEXlang workflow

Edit the APEXlang files and review them. Committing first is optional:
publish imports the files on disk, and the shared database is the source of
truth. Before importing into shared DEV, tell teammates which app ID is being published and check for
unsaved or in-progress Builder edits. Then run:

```bash
scripts/team.sh publish 100 --env dev
```

The exporter records the app's `last_updated_on` value from Oracle before it
reads APEXlang, then checks the value again when the export completes. If the
app changed during export, it refuses to install that source. The DEV drift
guard compares the current Builder value with this database-time baseline, so
the workstation's time zone does not affect the check. If Builder is newer,
export and reconcile before importing. `--force` bypasses only the drift guard
and should be used only after the discrepancy is reviewed. Oracle stores this
revision at one-second precision; if the revision matches the database's
current second, export and publish fail closed and ask you to retry after one
second. This persisted timestamp cannot reveal unsaved Builder edits, so
coordinate with teammates before publishing. Staging and production promotion
uses the separate `deploy` command.

APEX does not stamp `last_updated_on` while importing, so an app installed or
published from APEXlang has no Builder timestamp until someone saves it in
Builder. To make each import identifiable, a DEV publish first stamps a
publish tag onto the end of the application version in `application.apx`:

```text
version: "V2 Powered By xxx [ASHARIF-2026-09-26r001]"
```

The tag is `DEVELOPER_NAME` from `.env`, the publish date, and a counter that
counts up with each publish of that date, whoever published, and restarts at
`r001` on a later date. The date never moves back, so a tag is never reused.
The export marker records the live version with the Builder timestamp, and the
drift guard refuses to publish when the live version differs from your
baseline, which is how it detects a teammate's import. Commit the stamped
`application.apx` after a successful publish. If the import fails, publish
restores the unstamped file. The tag appears wherever the theme renders
`#APP_VERSION#`, such as the Universal Theme footer, and `deploy` ships it to
staging and production unchanged.

After a successful DEV import, `publish` exports the app again and compares the
APEXlang file names and bytes with the local source, excluding the local
deployment descriptors and export marker. It advances the drift baseline only
when that source matches and the live Builder revision stayed stable during the
verification export. If SQLcl reports an error, the source differs, or the
revision is ambiguous, publish fails and leaves the old baseline in place.
SQLcl can exit successfully without importing, for example when a descriptor
names an unknown workspace, so publish also requires its `Import successful.`
line.
Publish preflight also requires the selected application tree to be physically
inside the checkout and rejects symbolic links and reparse points.

When publish refuses, see [docs/publish-rules.md](docs/publish-rules.md) for
every rule, what each message means, and what to do.

## Schema migrations

Create one dated folder per migration. Put each SQL step in its own numbered
file and list the folder when checking or applying it:

```text
migrations/2026-09-27_create-customers-r001/
├── 001-create-table.sql
├── 002-create-index.sql
├── 003-create-view.sql
└── checks.json
```

The folder date is a creation date. Names sort newest first only when the file
browser is sorted descending; they do not control its sort setting. SQL steps
run in ascending sequence, while multiple folders run in the explicit
command-line order. `create-customers-r001` and
`2026-09-28_create-customers-r002` are separate sequential migrations; the
second contains the follow-up change. Keep a migration and its `checks.json`
immutable once an apply attempt may have started. A recovery belongs in the
next revision. Use `scripts/team.sh revise <folder> [--reason TEXT]` to copy
the SQL files and checks into the next revision, preserve their names and
numbering, and add a `Supersedes` line to the new README. The source remains
unchanged and receipts are not copied. `revise --check <folder>` inspects local
attempt and receipt evidence without connecting; it exits 0 for unlocked, 1
for locked, and 2 when evidence is unknown or unreadable. See the
[migration rules](docs/migration-rules.md) for its limits and the exact
`apply-not-started` classification.

For eligible data changes, rehearse ordered folders against the configured
target and save a JSON report:

```bash
scripts/team.sh migrate \
  migrations/2026-09-27_seed-customers-r001 \
  migrations/2026-09-28_assign-customers-r001 \
  --env dev --rehearse --report scratch/customer-seed-rehearsal.json
```

Rehearsal runs analyzer-approved DML files in one SQLcl transaction,
evaluates postconditions in that transaction, then rolls back and rechecks
preconditions. DDL, implicit-commit statements, and files the analyzer cannot
prove transaction-safe are skipped and reported as `not rehearsable`. It
creates no migration receipt or write-attempt marker. See the
[migration rules](docs/migration-rules.md) for the classification, rollback
proof, report fields, and exit codes.

Run a selected live preflight and apply with an explicit environment:

```bash
scripts/team.sh check-conflicts \
  migrations/2026-09-27_create-customers-r001 --env dev
scripts/team.sh migrate \
  migrations/2026-09-27_create-customers-r001 --env dev
```

Use `migration-plan` to review local folders, counts, hashes and evidence
before choosing an explicit order. Offline reports need no `.env` or SQLcl;
`--live` performs a guarded read-only preflight for selected folders and an
explicit environment. It never applies SQL. See
[migration planning](docs/migration-planning.md) for the report fields,
deferred preconditions and ordering limits.

```bash
scripts/team.sh migration-plan --format markdown
scripts/team.sh migration-plan \
  migrations/2026-09-27_create-customers-r001 \
  migrations/2026-09-28_assign-customers-r001 --live --env dev --format json
```

The offline `--local` checker analyzes selected files only. Live preflight
compares the selected batch with the target catalog, but cannot see pending
files in another developer's independent repository. Two developers can pass
before either writes; preflight runs again before apply, though a concurrent
change can still race it. See [docs/migration-rules.md](docs/migration-rules.md)
for coverage and recovery limits. Live catalog captures retry changing object
name/type inventories up to `MIGRATION_PREFLIGHT_INVENTORY_RETRIES` times
(default `3`); the setting is optional in `.env`.

`checks.json` requires read-only preconditions and postconditions.
`status.<env>.json` appears only after the committed result has been verified
through a fresh connection. It is local evidence, not a shared deployment
ledger. Migration SQL can use standalone slash terminators for PL/SQL blocks,
`CREATE TYPE`, `CREATE LIBRARY`, `CREATE JAVA`, and `CREATE MLE MODULE`.
SQLcl client commands such as `SET DEFINE`, `PROMPT`, and `WHENEVER` are
rejected before connecting.

For staging or production, configure the existing connection and expected
user plus `STAGING_SCHEMA` or `PROD_SCHEMA`. The migration schema can differ
between environments, so these settings are explicit and never inferred from
DEV. Direct staging and production applies require interactive confirmation.

Compare selected live object names or prefixes with `compare-schema`:

```bash
scripts/team.sh compare-schema --from dev --to staging \
  --object CUSTOMERS --object ORDERS
scripts/team.sh compare-schema --env prod --pattern 'HR_*' --pattern 'GL_*'
```

This reports current catalog drift for the selection. Status receipts can help
with follow-up review but cannot reliably prove which migration file caused a
shape: separate migrations may produce the same DDL, and a manual change can
mimic a migration.

Use `compare-env` for complete, paged readiness comparisons by object name:

```bash
scripts/team.sh compare-env --from dev --to staging
scripts/team.sh compare-env --from dev --to staging \
  --section tables --section columns --section constraints --section triggers
scripts/team.sh compare-env --from dev --to staging --format markdown
```

The report identifies incomplete or unavailable catalog sections and reports
the limits of each comparison. It is read-only and requires SQLcl 26.3.0.0 or
newer.

### Generate an environment baseline

Copy [the example](docs/baseline.example.json) to the project root as
`baseline.json`, then set the project schemas, object filters, grant policy,
sequence mappings and reference-data allow-list. Export the configured source
and generate new granular migration folders for review:

```bash
scripts/team.sh baseline export-source --from dev
scripts/team.sh baseline export-grants --from dev
scripts/team.sh baseline export-data --from dev
scripts/team.sh baseline build --from dev --to staging
scripts/team.sh baseline build --from dev --to staging --data
scripts/team.sh baseline build --from dev --to staging --bundle customer-status
scripts/team.sh baseline build --from dev --to staging --bundle customer-status --data
scripts/team.sh baseline filter-ords --exclude-module legacy.api \
  --input scratch/ords/schema.sql --output scratch/ords/schema-filtered.sql
```

The builder can create separate `baseline-structure`, `baseline-grants`, and
`baseline-code` folders, plus a separate `baseline-data` folder when `--data`
is selected. Add `--bundle <name>` to combine nonempty structure, grants and
code output into one `baseline-bundle-<name>` folder per target schema; a
three-folder output becomes one, and reference data remains separate. This
adds no repository-wide migration-folder count limit. Excluded sensitive columns never enter reference-data
exports. Generated folders are reviewed and applied through the ordinary migration
workflow; baseline commands do not apply SQL. See
[baseline generation](docs/baseline.md) for its capture, data and recovery
limits. Live baseline commands require SQLcl 26.3.0.0 or newer.

## Staging and production deployments

For direct promotion, configure the target connection/user pair in `.env` and
provide a per-app descriptor. The tool prints the selected app, workspace,
and schema before asking for confirmation:

```bash
scripts/team.sh deploy 100 --env staging
scripts/team.sh deploy 100 --env prod
```

Direct staging and production imports require `Deploying to <ENV>. Proceed?
[y/N]`. To prepare a DBA handoff without opening a database connection, use:

```bash
scripts/team.sh deploy 100 --env prod --manual
```

The runbook includes the explicit deployment descriptor and SQLcl identity
check. A human DBA executes it using an approved saved connection. App
promotion uses deployment descriptors; schema migrations use the separate
`migrate --env` command and explicit target-schema settings.

## Upgrading from the template

Projects created from this template do not share its Git history, so updates
are copied file by file. `template-manifest.json` decides which repository
files the upgrade may touch: template scripts, tests, CI, and agent guidance
are upgraded; project files such as `AGENTS.project.md`,
`.agents/rules/project.md`, and `PROJECT.md` are created once and never
overwritten; application source, database mirrors, migrations,
`app_context/<id>/`, and `.env` are never touched, even when `.env` is tracked
in Git. Put project-specific
instructions in those placeholder files, not in `AGENTS.md` or `README.md`.
The engine also writes its fixed `.template-lock.json` metadata file, which
records the installed template commit and hashes.

Commit your work, then run:

```bash
scripts/team.sh upgrade-template --dry-run
scripts/team.sh upgrade-template
git status
```

A file you customized is kept when the template did not change it. When both
changed, the upgrade keeps your file, writes the new template version beside
it as `<file>.template-new`, and exits with status 1: merge the two, delete the
`.template-new` file, and commit. The next upgrade refuses to run while any
`.template-new` file remains. The upgrade records the installed template commit
and selected `templateRef` in `.template-lock.json`; commit it with the upgraded
files. Future upgrades and update notices use that recorded branch or tag. Legacy
locks without `templateRef` stay silent during update checks and require an explicit
`--ref <branch-or-tag>` before applying an upgrade. Use `--ref <tag>`
to install a specific template version and `--source <url>` for a fork. If the
upgrade reports that `.env` needs attention, compare it with `.env.example`.
A differing `.env.example` on the first upgrade also leaves an
`.env.example.template-new` review copy; merge it into the example before
reviewing any corresponding changes to your own `.env`.
Files removed after they were recorded in `.template-lock.json` remain deleted
(`KEEP-DELETED`). Keep that lock when cleaning a clone. New upstream files can
still be created; review tests and GitHub automation after future upgrades.
If the upgrade is interrupted (Ctrl-C or `kill`), it puts back every file it had
replaced and says `the project was left as it was`; run it again.

### Recover an older template lock

An existing 26.1 project may have inherited
`https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_TEAM.git` in its
`.template-lock.json` upstream. That repository now uses the 26.2 manifest
contract, so the 26.1 upgrade can refuse it with `unsupported template manifest
schemaVersion`. Correcting the local manifest alone does not change the source:
precedence is explicit `--source`, then the lock's upstream, then the manifest.

For this historical 26.1 lock, start from a clean working tree and explicitly
select the 26.1 release repository. Review the dry-run before applying:

```bash
git status --short
scripts/team.sh upgrade-template --source https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_26_1.git --dry-run
scripts/team.sh upgrade-template --source https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_26_1.git
git diff
```

The dry-run leaves files and the lock unchanged. Apply records the explicitly
selected source in the new lock and keeps the ordinary conflict rules: local
customizations stay in place, conflicts produce `.template-new` review copies
and exit 1. Merge each conflict, remove its review copy, and review and commit
the upgraded files together with `.template-lock.json`. Keep the existing lock
for its file hashes and intentional-deletion history. Use the same `--ref` on
both commands when selecting a particular reviewed template version.

A deliberately selected fork remains the source recorded in its lock. Use this
override only when choosing to move that project back to the 26.1 release line.

A project upgraded to a template version with multi-schema support needs no
`.env` change: one value per key is still the single-schema setup. Its next
`scripts/team.sh backup-db` also mirrors each schema's private synonyms under
`database/<SCHEMA>/synonyms/`; review and commit that new folder. The upgrade
never moves existing migration folders, and the flat
`migrations/YYYY-MM-DD_<name>-rNNN/` layout stays valid while `CODE_SCHEMA` has
one schema.

A project upgraded to a template version with ORDS support needs no `.env`
change either: ORDS stays disabled until all three `ORDS_*` keys are added. The
upgrade delivers the ORDS scripts, tests and [docs/ords-export.md](docs/ords-export.md)
as template files and never touches `database/`, so an existing
`database/<SCHEMA>/ords/` export, your `.env`, apps and migrations are kept.

Projects created before `template-manifest.json` existed do not have the
upgrade script yet. Run it once from a fresh template clone. When the target
repository has no `.template-lock.json`, the source resolves from its own
`template-manifest.json`; `--source` overrides that value, and a lock's upstream
is used when no explicit source is supplied:

```bash
git clone https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_26_1.git /tmp/apex-template
python3 /tmp/apex-template/scripts/upgrade_template.py --project-root . --source https://github.com/ash2osh/APEX_PROJECT_TEMPLATE_26_1.git
```

That first run has no lock, so every file that differs from the template is
reported as a conflict instead of being overwritten. Keep the project clean
before running it; conflicts must be reviewed and merged manually.

The engine stages updates and restores them if a filesystem operation fails.
If it reports an incomplete rollback, keep the named recovery directory and
restore those backups before retrying the upgrade.

## Command reference

`doctor` detects the full database version and `COMPATIBLE` separately for each
checked DEV target, including a configured ORDS target. It does not write these
observations into `.env` or change database settings. Missing, malformed or
unavailable detection makes the check fail; it is not a compatibility pass.
The observations belong to the displayed target identity and this run: do not
reuse DEV results as proof for staging or production. Before choosing a feature
for several targets, establish their supported versions and compatibility
settings through authorized read-only checks; if unavailable, report them as
unknown. Version and compatibility do not prove feature privileges or availability.

| Command | Purpose |
| --- | --- |
| `scripts/team.sh doctor` | Validate `.env`, check the DEV SQLcl identity and report the detected database version and `COMPATIBLE`. |
| `scripts/team.sh dev-test --env dev --schema NAME --plan\|--run` | Plan or run the six built-in DEV checks, or an explicitly selected project suite; fixtures are retained by default. See [DEV test runner](docs/dev-test.md). |
| `scripts/team.sh dev-test --report <run-id> [--format text\|json\|markdown]` | Render saved evidence without connecting to a database. |
| `scripts/team.sh dev-test --cleanup <run-id>` | Explicitly clean supported recorded artifacts; project suites without a cleanup contract remain manual. |
| `scripts/team.sh export <id>` | Export one numeric app from shared DEV Builder. |
| `scripts/team.sh publish <id> --env dev` | Drift-check and import one app to DEV. |
| `scripts/team.sh check-conflicts <folder> [...] --env <env>` | Preflight selected migrations against a live schema. |
| `scripts/team.sh check-conflicts <folder> [...] --local` | Analyze selected migrations without a connection. |
| `scripts/team.sh migration-plan [<folder> ...] [--schema NAME] [--format text\|json\|markdown]` | Inventory local migration folders or run a selected guarded read-only live preflight. |
| `scripts/team.sh migrate <folder> [...] --env <env> [--verbose] [--rehearse] [--report <file>]` | Verify and apply selected migration folders, or rehearse eligible DML in one transaction and roll it back. |
| `scripts/team.sh new-migration <name> --source TYPE:NAME [...] --env dev [--schema NAME]` | Start `migrations/<SCHEMA>/<today>_<name>-r001/` from the source live on DEV: one editable step per object, preconditions that refuse the apply if that source changes first, postconditions that each object is VALID. Read-only. |
| `scripts/team.sh revise <folder> [--reason TEXT]` | Copy a migration to its next revision; the old folder stays unchanged. |
| `scripts/team.sh revise --check <folder>` | Report whether local receipt or attempt evidence locks a folder; exit 0/1/2 for unlocked/locked/unknown. |
| `scripts/team.sh verify <folder> [...] --env <env> [--phase pre\|post\|both] [--only-failed] [--format text\|json] [--jobs N]` | Evaluate migration checks read-only; false checks return 1 and errors return 2. |
| `scripts/team.sh rollout <manifest.json> --env <env> [--from-step N] [--dry-run] [--report <file>]` | Run a frozen ordered deployment plan; staging and production use one manifest-wide confirmation. |
| `scripts/team.sh compare-schema --env <env> --object <name>` | Compare selected live schema objects read-only. |
| `scripts/team.sh compare-env --from <env> --to <env> [--section <name>] [--format text\|json\|markdown]` | Compare complete, paged environment catalogs by object name. |
| `scripts/team.sh baseline export-source --from <env>` | Export exact stored source, compiler settings and view text to scratch. |
| `scripts/team.sh baseline export-grants --from <env>` | Export configured object grants and direct system privileges. |
| `scripts/team.sh baseline export-data --from <env>` | Export allow-listed reference rows while excluding configured sensitive columns. |
| `scripts/team.sh baseline build --to <env> [--from <env>] [--data] [--bundle <name>]` | Generate granular or optionally bundled structure, grant and exact-source folders, plus separate optional reference-data folders. |
| `scripts/team.sh baseline filter-ords --exclude-module NAME [...] --input <file> --output <file>` | Remove complete named modules from an ORDS export. |
| `scripts/team.sh backup-db` | Refresh local table and code metadata mirrors (and ORDS, when configured). |
| `scripts/team.sh backup-ords` | Export ORDS (REST) metadata read-only to `database/<SCHEMA>/ords/schema.sql`. |
| `scripts/team.sh deploy <id> --env <staging\|prod> [--manual]` | Confirm a promotion or print a DBA runbook. |
| `scripts/team.sh upgrade-template [--dry-run]` | Update template-owned files; never overwrites project files. |
| `scripts/team.sh skills setup none\|superpowers\|mattpocock\|both [--primary superpowers\|mattpocock]` | Set up optional, pinned workflow packs locally. |
| `scripts/team.sh skills status [--format text\|json]` | Inspect repository-managed packs offline. |

`verify` uses read-only check sessions, confirms the target identity for every
session and never applies migration SQL. `rollout` hashes all referenced input
files before execution, stops at the first failed step and records private
receipts under `scratch/`. A resume requires matching receipts for the same
manifest, environment and source hashes. `--dry-run` validates the manifest
and prints its hashes without running steps. See the [rollout rules and
manifest schema](docs/migration-rules.md#rollout) and the
[example manifest](docs/rollout-manifest.example.json).

Exit status, the same in Bash and PowerShell:

| Status | Meaning |
| --- | --- |
| 0 | Done; for `check-conflicts`, `compare-schema`, and `compare-env`, nothing found; for `migration-plan`, inventory is complete or live preflight has no conflict/error and no selected lock; for `revise --check`, the folder is unlocked. |
| 1 | `check-conflicts` found conflicts, `compare-schema` or complete `compare-env` found differences, `migration-plan` found a live conflict or selected immutable folder, `verify` found false checks, `revise --check` found a lock, a `[y/N]` prompt was declined, `upgrade-template` left `.template-new` files to merge, or `.env` is invalid (`project environment error: ...`). |
| 2 | Refused or failed; the message says why and what changed. `migration-plan` uses 2 for invalid selection or incomplete evidence; `compare-env` uses 2 for incomplete capture. Also `migrate` interrupted while a SQL step runs ("may be partially applied"). |
| 130 / 143 | Stopped by Ctrl-C / by SIGTERM (`kill`). |

SIGTERM is for Bash: `team.sh` hands its process to the command it runs, so a
`kill` reaches it. PowerShell 7 on Linux and macOS cannot run any cleanup on
SIGTERM, so `kill` ends `team.ps1` while the Bash helper or SQLcl it started
carries on (a migration may finish and write its receipt); its scratch folder
stays behind. Stop a PowerShell run with Ctrl-C, or signal its whole process
group (`kill -TERM -- -<pgid>`). Windows has no SIGTERM.

`scripts/team.ps1` exposes the same commands for PowerShell. Migration and
deployment helpers use Bash, such as Git Bash on Windows; `team.ps1` finds Git
Bash itself, and `TEAM_BASH` names a different `bash.exe` when it cannot.

## Optional knowledge graph

Graphify is optional; every command in this template works without it, and
agents fall back on grep. It indexes a domain-only corpus (`apps/`, `database/`,
and `app_context/`) through a repository-owned APEXlang extractor, so `.apx`
files are read as APEX architecture — containment, navigation, authorization,
database reads and writes, and PL/SQL calls — rather than as generic SQL. The
graph reflects this repository's files; export first when it must describe
current Builder state.

Install Graphify and its SQL parser (the distribution is `graphifyy`, the
command is `graphify`), then configure a supported semantic backend:

```bash
uv tool install graphifyy --with tree-sitter-sql
python3 scripts/setup_graphify_apx.py
graphify extract . --force
```

- `python3 scripts/setup_graphify_apx.py --verify` checks the installation
  without changing it; rerun setup after **every Graphify upgrade**.
- `python3 scripts/check_graphify_apx.py` before every build, then
  `python3 scripts/check_graphify_apx.py --graph graphify-out/graph.json`
  afterward. Both must pass: Graphify can exit zero after skipping parser
  failures. This checks APEXlang parsing and file presence, not live runtime
  validity or semantic completeness; it uses the default output directory's
  saved corpus exclusions and Git-ignore setting.
- `graphify update .` after APEXlang or database changes (local, no API cost).
- `graphify extract .` after changing `app_context`.
- `python3 scripts/setup_graphify_apx.py` then `graphify update .` after the first
  `backup-db` or when tables or packages change, so pages link to the real
  database nodes instead of cached stubs.
- `graphify extract . --force` after changing `.graphifyignore`.

`graphify-out/` is local and gitignored. See
[`.agents/workflows/graphify.md`](.agents/workflows/graphify.md).

## Agent guidance

Agents follow the same app ID, descriptor, drift, migration, and deployment
rules as developers. Review source before editing; do not run database-writing
commands unless the user asked; coordinate with the team before importing into
shared DEV. Never claim an unavailable live check passed. See [AGENTS.md](AGENTS.md)
for the full repository contract, [migrations/README.md](migrations/README.md),
and [docs/migration-rules.md](docs/migration-rules.md) for migration naming,
verification, and comparison limits. For browser runtime checks, see
[Chrome DevTools MCP](docs/CHROME_DEVTOOLS_MCP.md) and use the project browser
[skill](.agents/skills/chrome-devtools-mcp/SKILL.md).
