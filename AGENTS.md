# Team APEX agent contract

This repository is the APEX 26.1+ / APEXlang team template. The template
repository follows its normal branch and pull-request process: push a
branch and open a pull request, never push to `main`, and run
`python3 scripts/pre_push_check.py` first (see
[docs/ci-checks.md](docs/ci-checks.md)). A project
created from it gives each developer a separate Git repository; the team
shares its development Oracle database and APEX workspace, not Git history.
Never exchange downstream commits or assume a colleague's repository changes
are present locally. A Git branch does not isolate shared database or Builder
state.

## Conversation style

At the start of every conversation, before your first reply:

1. Read `AGENT_STYLE` (default `standard`; one of `standard`, `concise`, `teaching`,
   `asharif-style`) and `AGENT_STYLE_LEARNING` (default `on`) from the root `.env`.
2. Read `.agents/styles/<AGENT_STYLE>.md` and follow it for the whole conversation.
3. Read `.agents/styles/personal.md` if it exists and apply it over the style.
4. Open your first reply with one line: `Style: <name>`, plus ` + personal layer (N entries)`
   when `personal.md` has entries. If the value is invalid or a file is missing,
   fall back to `standard` and say so in that line.

Precedence, highest first: this file, `.agents/rules/agent-safety.md` and the project rules; then
`personal.md`; then the style. A style or a personal entry never relaxes a gate (commits and
pushes, database writes, migrations, imports, claiming a check that did not run).

Learning, unless `AGENT_STYLE_LEARNING=off`: when the developer states a preference or corrects your
format, or makes the same choice three times, add one dated line to `personal.md` under the matching
heading and say `Recorded in personal.md: <entry>` in the same reply. Never record silently. Replace
an entry that the new one contradicts. Keep the file under about 40 lines. Never record credentials,
hosts, customer, employee or business data, project or schema names, or anything that loosens a
safety rule. Never commit or push `personal.md` on your own initiative. See
[.agents/styles/README.md](.agents/styles/README.md).

## Optional workflow packs

Read `.agent-skills.json` at task startup (missing means `none`). It records
`selection` (`none`, `superpowers`, `mattpocock`, `both`) and `primary`.
Only apply an enabled repository workflow pack. With both selected, use the
primary pack's process by default; use the other for an explicit user request
or task override, without duplicating whole workflows. Direct user instructions
and project safety rules take precedence over either pack.

Set up packs only when requested, using `scripts/team.sh skills setup <selection>`
(or `team.ps1`). Use `skills status` for offline installation evidence. Selection
controls repository-managed copies, not global skills or enabled app plugins;
report those separately when they affect a request to use neither.

The 11 template-authored domain/setup skills remain
independent of optional workflow packs. After installing Matt's pack, invoke
`/setup-matt-pocock-skills` when requested and put its project guidance in
`AGENTS.project.md`, preserving existing instructions, instead of template-owned
`AGENTS.md`/`CLAUDE.md`. See [workflow skill setup](docs/workflow-skills.md).

## Configuration and application source

- Copy `.env.example` to root `.env`, set `DEVELOPER_NAME` to the
  developer's uppercase name, and use SQLcl saved connection names. After
  local validation, review and keep this credential-free configuration in
  each developer's own downstream Git repository. The
  default points the table, code, and APEX profiles at the same DEV
  connection. Keep these profile values aligned unless the project needs
  separate connections. Staging and production connection/user pairs are
  optional. Each profile's schema, connection, and expected-user keys accept
  position-aligned comma lists; one value keeps current behavior. Use
  `--schema <NAME>` to narrow any command. `doctor` and `backup-db` default to
  all schemas. Never put credentials in `.env` or tracked files. An optional,
  independent `ORDS_SCHEMA`, `ORDS_SQLCL_CONNECTION` and `ORDS_EXPECTED_USER`
  profile (all three or none) enables the read-only ORDS export; its session
  user must equal the REST schema.
- Use numeric APEX application IDs in commands and descriptors. Store each
  app's APEXlang source and `deployments/{dev,staging,prod}.json` under
  `apps/<parsing-schema>/<app-id>/`. `apps/templates/deployments/` contains
  descriptor examples. Each descriptor names the target workspace, numeric
  app ID, and parsing schema explicitly.
- Keep APEXlang and SQL files in LF line endings. Review generated source and
  database mirror changes before committing.
- The shared database is the runtime source of truth. Do not add custom team
  metadata tables, mutexes, checkout rosters, or database-backed migration
  ledgers.

## Team workflow

- **Builder-first:** Coordinate with teammates before editing a shared app in
  Builder. Run `scripts/team.sh export <app-id>`, review the APEXlang diff, and
  commit it. Export records the observed Builder state; do not import as part
  of this route.
- **File-first:** Edit the exact APEXlang source; committing before publish
  is optional, since publish imports the files on disk. Before importing
  to shared DEV, tell the team which numeric app ID is being published and
  check for in-progress Builder edits. Run
  `scripts/team.sh publish <app-id> --env dev`. The drift guard compares the
  live app's update time with the database-time revision captured before the
  latest export. The exporter also checks that Builder did not change during
  that export. Oracle records this value at one-second precision, so the
  exporter and guard fail closed when it matches the current database second.
  This timestamp cannot see unsaved Builder edits; communicate with teammates
  before publishing. APEX leaves it null after an APEXlang import, so each
  DEV publish stamps `[DEVELOPER_NAME-YYYY-MM-DDrNNN]` onto the application
  version in `application.apx` before import, and the guard also refuses when
  the live version differs from the baseline (a teammate's import). Commit the
  stamped `application.apx` after publish; `deploy` ships the tag unchanged.
  The guard refuses to overwrite newer Builder work. Export and reconcile
  before retrying. After import, publish re-exports the app and requires
  exact APEXlang file and byte equality before it advances the DEV baseline.
  A failed or ambiguous verification leaves the old baseline in place, so the
  next publish still refuses newer Builder state. Use `--force` only when the
  user explicitly directs an override after review. When publish refuses,
  follow [docs/publish-rules.md](docs/publish-rules.md), which lists every
  refusal, its meaning, and the fix.
- **Migrations:** Put each migration in
  `migrations/YYYY-MM-DD_<name>-rNNN/` with consecutive named SQL steps such as
  `001-create-table.sql`, plus `checks.json`. No developer name belongs in the
  path. Keep source immutable after a write attempt; a follow-up uses the next
  revision folder. Run `scripts/team.sh check-conflicts <folder> --env dev`
  before applying with `scripts/team.sh migrate <folder> --env dev|staging|prod`.
  Checks cover only selected local migrations and observed live state; they
  cannot see another independent repository's pending files. Staging and
  production migrations require `STAGING_SCHEMA` or `PROD_SCHEMA` in addition
  to the existing connection and expected-user settings. Receipts are written
  only after a verified apply. Multi-schema projects use
  `migrations/<SCHEMA>/…`; one migration changes one schema. See
  [docs/migration-rules.md](docs/migration-rules.md) for naming, ordering,
  recovery, and detection limits.
- **Schema comparison:** Use `scripts/team.sh compare-schema --env staging
  --object CUSTOMERS` or `--from dev --to prod --pattern 'HR_*'` to compare
  selected live objects. This reports schema drift; local receipts cannot
  reliably attribute a shape to one migration file.
- **Daily change record:** A package migration holds the whole source, so Git
  cannot show what changed. For each day with code work, keep
  `ai_generate/YYYY-MM-DD/` with the readable diff of each migration
  (`python3 scripts/migration_diff.py migrations/<SCHEMA>/<folder>`, local files
  only, run before `backup-db` refreshes the mirror) and one `WALKTHROUGH.md` for
  that day. Commit the folder with the work. See
  [docs/daily-change-record.md](docs/daily-change-record.md).
- **Promotion:** Put an explicit deployment descriptor in the application
  source. Use `scripts/team.sh deploy <app-id> --env staging` or `--env prod`;
  each direct import requires the displayed `[y/N]` confirmation. Add
  `--manual` to print a DBA runbook without connecting. A deployment writes
  to the selected APEX workspace and parsing schema.
- **Other commands:** `scripts/team.sh doctor` validates `.env` and performs a
  read-only SQLcl identity check. `scripts/team.sh backup-db` refreshes the
  local table and code mirrors, and the ORDS mirror when the ORDS profile
  exists. `scripts/team.sh backup-ords` exports ORDS metadata only: it never
  enables REST, imports, changes ORDS configuration, creates metadata, grants
  privileges or commits, and it never exports OAuth clients or secrets. Read
  [docs/ords-export.md](docs/ords-export.md) before changing it.

## Optional Tooling

`graphify` (a knowledge-graph indexer exposed via ignored `graphify-out/`) is
optional; every script works without it. Its rules live in
[`.agents/rules/graphify.md`](.agents/rules/graphify.md) and
[`.agents/workflows/graphify.md`](.agents/workflows/graphify.md), and every rule
is gated on `graphify-out/graph.json` existing. Install it with
`uv tool install graphifyy --with tree-sitter-sql`, run
`python3 scripts/setup_graphify_apx.py` (rerun after every Graphify upgrade;
`--verify` checks without changing anything), then `graphify extract . --force`.
The corpus is a domain allowlist of `apps/`, `database/`, and `app_context/`.
Graphify links cross-schema references and mirrored synonyms when their targets
are present in the database mirror. The graph reflects this repository's
files, not shared Builder state. When the graph exists, each new conversation
starts a background `graphify update .` (see the graphify rules for its
guards); it is skipped when Graphify is absent.

## Template update check

At the start of every new conversation, run once in the background:
`python3 scripts/check_template_update.py`. This read-only check compares the
lock's `commit` with its recorded `templateRef` (branch or tag), using a portable
10-second timeout on each Git call. It does not fetch objects into the project.

- Stay silent when the lock/ref is missing or invalid, a commit is pinned,
  the ref is ambiguous, the network/Git is unavailable, or the commits match.
- If the command prints an update notice, include it once in the first reply,
  or the next progress update if the background result arrives later. Do not
  delay the reply while waiting for it.
- Never run the upgrade or commit on your own initiative; the developer decides.

## Project instructions

- After cloning into a new downstream project, follow the
  [post-clone cleanup](docs/GETTING_STARTED.md#post-clone-cleanup) instructions:
  establish `.template-lock.json`, then remove inherited template-maintenance
  tests, GitHub workflows/Dependabot and historical planning documents. This
  cleanup applies to downstream projects, not the original template repository,
  which retains its tests and CI. Preserve project-specific regression tests
  when cleaning an existing project. Keep `.env`, operational scripts, agent
  guidance, the manifest and upgrade lock.
- `AGENTS.md`, `CLAUDE.md`, `README.md`, and `.agents/rules/agent-safety.md`
  belong to the template; `scripts/team.sh upgrade-template` replaces them.
  Put project-specific agent instructions in `AGENTS.project.md`, project
  rules in `.agents/rules/project.md`, and the project overview in
  `PROJECT.md`. The upgrade never overwrites those files.
- Read `AGENTS.project.md` and `.agents/rules/project.md` after this file.
  When they conflict with this file, ask the user which applies.

## Rules for coding agents

- Before reporting a defect or changing behaviour in a review or test run,
  check [docs/known-limitations.md](docs/known-limitations.md). The behaviour
  listed there is deliberate: do not report or "fix" it again unless it no
  longer matches that page.
- Before writing PL/SQL for APEX automations, workflow activities, task
  actions, or background execution chains, read
  `.agents/skills/apex-background/SKILL.md`.
- Read the relevant `.apx`, APEXlang, SQL, and deployment descriptor files
  before editing them. Preserve the app's numeric ID and explicit workspace
  mapping. Do not invent a live workspace, schema, connection, or migration
  result.
- Treat export, migration, publish, and deployment commands according to
  their database effects. Do not run a migration, import, or deployment unless
  the user requested that operation. Export only when requested because it
  refreshes tracked source from shared Builder state.
- Coordinate shared DEV app imports with the human team. There are no database
  pause tables or acknowledgement commands in this workflow. Never claim that
  team communication or a live database check happened unless it did.
- Do not commit or push silently. Follow explicit instructions for commits;
  do not push unless asked.
- If SQLcl, the database, or a requested environment is unavailable, report
  the check as unknown or unavailable rather than passed.
- Before writing version-dependent SQL or PL/SQL, obtain database version and
  compatibility information for the intended target through the configured,
  identity-guarded read-only flow. `scripts/team.sh doctor` (or `team.ps1 doctor`)
  reports the full database version and `COMPATIBLE` for each checked DEV target;
  existing migration and schema-comparison observations also record a database
  version, but do not establish its compatibility setting. Do not infer staging
  or production capabilities from DEV. For code intended for several targets,
  use features supported by all of them, within their compatibility settings.
  Use modern SQL and PL/SQL when supported and appropriate; preserve behavior,
  established interfaces and data conventions. Do not rewrite working code only
  to modernize it or assume different constructs have identical semantics.
  Check Oracle documentation or the `db` skill for feature-specific requirements;
  a version observation alone does not prove every feature is enabled or usable.
  If the target is unavailable or its compatibility is unknown, report that and
  ask once for the required compatibility level before choosing version-dependent
  features; continue unrelated work. Never guess or maintain a database-version
  setting in `.env`, and never change database compatibility to fit the code.

See [README.md](README.md) for setup and command examples, and
[migrations/README.md](migrations/README.md) and
[docs/migration-rules.md](docs/migration-rules.md) for the migration contract.
