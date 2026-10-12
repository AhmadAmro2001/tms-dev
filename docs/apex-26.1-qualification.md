# APEX 26.1 backport qualification

## Scope

This qualifies the candidate on `codex/apex-26.1` at code commit `70e5a3a`,
based on `5178f57a56d919337d1e7d23fc809275cfb8488e`. The port preserves the
APEX 26.1 descriptor contract and avoids APEX 26.2 APIs. It carries selected
release-neutral migration safety improvements: read-only verification, frozen
rollout, DML rehearsal, safe next-revision creation, honest apply-not-started
classification, and stable catalog preflight with direct synonym/grant
evidence.

The separate `compare-env` and baseline-capture tools are outside this
backport's scope. No project APEX application import/export or migration was
run; the live checks below qualify the target installation, database identity,
and APEX entry points rather than application-specific behavior.

## Qualification matrix

| Target | Database | APEX | ORDS | SQLcl | OS / branch | Outcome | Cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Offline suite | N/A | N/A | N/A | 26.3.0.0 installed | Linux; `codex/apex-26.1` | **Pass:** `python3 -m unittest discover -s tests` — 1,080 tests passed, 26 skipped; `git diff --check` passed. | No database fixture |
| Local isolated target `local-apex-261` | Oracle Free image `23.26.3.0`; PDB `FREEPDB1` | `26.1.5`; patch `39179920`, version 5 | Image `26.3.0` | 26.3.0.0 | Linux; code commit `70e5a3a` | **Pass for installation and read-only smoke checks.** Evidence below. | Retained new volume `oradata-apex261`; no fixture schema created. Existing 26.2 containers remain stopped and their `oradata-26ai` volume is preserved. |
| Windows offline suite | N/A | N/A | N/A | 26.3.0.0 installed; no database session used | Windows `10.0.26300`; `codex/apex-26.1` worktree based on `423573d`; Python 3.14.5; Windows PowerShell 5.1.26100.9444 and PowerShell 7.6.5; Git for Windows 2.54.0 | **Pass (offline only):** `py -3 -m unittest discover -s tests -v` — 1,076 tests passed, 45 skipped; `git diff --check` passed. | No Docker container, volume, database, or APEX application was changed |

## Live target evidence

- The official APEX 26.1 base archive matched SHA-256
  `06df14e7c8465747ee45c36c5a0b09821bf2b244db0e201d3cc44abb0403f023`.
  The Dropbox patch archive matched SHA-256
  `597df8641d0deb02c8be5774225c4f8d7f742500dadd81a7810c239ee80ccd17` and
  passed ZIP integrity validation. Its README identifies APEX 26.1.5, patch
  `39179920`, patch version 5, dated September 25, 2026. Oracle's download
  page lists the bundle as updated September 30, 2026, so the installed patch
  version is verified from the database, while the local archive's freshness
  against that later listing is not independently established.
- SQLcl reports `DBA_REGISTRY` APEX version `26.1.5`, status `VALID`, schema
  `APEX_260100`; `APEX_PATCHES` contains patch `39179920`, version `5`,
  installed October 12, 2026; `APEX_RELEASE` reports `26.1.5` and
  APEXlang `26.1.0+3102`. The `APEX_260100` schema has zero invalid objects.
- ORDS reports its default pool as `VALID`. `GET /i/apex_version.js` returns
  HTTP 200 and reports `26.1.5`. The modern Builder route
  `/ords/r/apex/app-builder/home` and Instance Administration route
  `/ords/r/apex/instance-admin` each reach their sign-in page. The legacy
  `/ords/apex` and `/ords/apex_admin` paths returned HTTP 404 in this setup.
- `scripts/team.sh doctor` passed using the saved local connection
  `local-apex261-sys` and a temporary read-only profile; output included
  `APEX_DOCTOR_VERIFIED:SYS`. The documented `verify-local` command is not
  exposed by this release branch's `team.sh` CLI, so that command could not be
  run here.

## Limits and remaining gate

- The live check does not qualify importing or exporting a project application,
  migrations, workflow execution, or application-specific APEXlang behavior.
- Both offline suite rows use fake SQLcl sessions and catalog fixtures; they do
  not replace live qualification. The Windows run qualified the native Windows
  PowerShell and Git Bash paths only at the test-suite level; it did not use the
  local Docker target or repeat the live database/browser smoke checks.
