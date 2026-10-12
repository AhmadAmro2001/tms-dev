# Windows APEX 26.1 Qualification and 26.2 Transition Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Windows qualification of `codex/apex-26.1`, resolve its confirmed failures, then move the local Docker APEX target and template checkout to 26.2 and qualify that combination.

**Architecture:** Keep the work sequential behind a green gate. First diagnose the 26.1 Windows failures, make focused fixes, and record verified results in the existing qualification matrix. Only after that phase passes, update the local Docker APEX/ORDS target, switch to the 26.2 template branch, and repeat the relevant checks.

**Tech Stack:** Windows 10, Windows PowerShell 5.1 and PowerShell 7, Python `py -3`, Git for Windows/Bash, Docker Desktop, SQLcl, and the repository's Python `unittest` suite.

**Spec:** User request in this conversation; `docs/apex-26.1-qualification.md`; `docs/known-limitations.md`; `AGENTS.md`.

## Global Constraints

- Complete and green the Windows 26.1 phase before changing the local Docker APEX/ORDS target or switching to the 26.2 template.
- Keep APEX 26.1 and 26.2 source/API contracts separate; use the matching branch and qualification notes for each phase.
- Preserve local database volumes and existing recovery evidence; do not run migrations, APEX imports, or deployments as part of offline qualification.
- Do not change machine-wide Git line-ending configuration to make tests pass; fix a confirmed repository/test issue at its source.
- Do not commit or push without an explicit request.

## Review Focus

- Git for Windows `core.autocrlf=true` may expose newline assumptions in generated SQL, cloned fixtures, and template-upgrade checks.
- POSIX file-mode assertions may not represent effective Windows ACLs.
- Tests that invoke Git Bash with native Windows paths may lose backslashes across the process boundary.
- PowerShell 5.1 and 7 may differ in native argument passing and command help/output behavior.
- Docker image tags, APEX patch level, ORDS version, and retained volumes must be checked before the 26.2 transition.

---

### Task 1: Diagnose and fix the Windows 26.1 suite

**Files:**
- Inspect: `tests/test_windows_support.py`, `tests/test_verify_checks.py`, `tests/test_backup_ords_cli.py`, `tests/test_documentation_contract.py`, `tests/test_migration_rehearsal.py`, `tests/test_ords_contracts.py`
- Modify only files implicated by confirmed root causes, including the focused tests and implementation/configuration they cover.

**Interfaces:**
- Consumes: current branch `codex/apex-26.1` and the Windows baseline from `py -3 -m unittest discover -s tests`.
- Produces: focused regressions that pass under the affected Windows shell/runtime and preserve Linux/macOS behavior.

- [x] Run the complete Windows baseline on `codex/apex-26.1`.
- [x] Capture exact failing test names and reproduce each failure by module or test method.
- [x] Trace failures to platform assumptions or implementation defects; check each proposed defect against `docs/known-limitations.md`.
- [x] Add or adjust the narrowest regression test before each implementation fix.
- [x] Re-run each focused test under the relevant PowerShell/Git Bash runtime until it passes.
- [x] Re-run `py -3 -m unittest discover -s tests` and require a green result.
- [x] Run `git diff --check` and confirm no test scratch files changed tracked source.

Baseline: 1,075 tests ran; 44 failures, 2 errors, and 45 skips. This is not a qualification pass. Root causes were WSL Bash path selection in three help checks, rollout syntax missing from both wrappers' help, Windows newline translation in the fake SQLcl, a fake template clone without the root `.gitattributes`, and a POSIX-only permission assertion. The focused Windows, rehearsal, verify, documentation, ORDS contract, and affected backup tests now pass.

### Task 2: Record the verified 26.1 Windows qualification

**Files:**
- Modify: `docs/apex-26.1-qualification.md`

**Interfaces:**
- Consumes: Task 1's passing test output and observed Windows/Python/PowerShell/Git/SQLcl versions.
- Produces: a Windows matrix row with exact tested versions, command, pass/skip counts, and limits.

- [x] Update the Windows outcome only after the complete required checks pass.
- [x] State clearly which checks were offline and which used the local Docker target.
- [x] Re-read the qualification page and run its focused documentation contract test.

### Task 3: Upgrade the local Docker target and qualify the 26.2 template

**Files:**
- Inspect the actual Docker compose/run configuration and retained container volumes before editing; this 26.1 template checkout contains no Docker configuration files.
- Modify only the confirmed local Docker configuration needed for the requested 26.2 APEX/ORDS target.
- Switch source checkout to the current 26.2 template branch only after Task 2 is green.

**Interfaces:**
- Consumes: a green 26.1 qualification and verified Docker image/volume identities.
- Produces: a preserved 26.1 target plus a running 26.2 target and a passing 26.2 template validation report.

- [x] Identify the exact local Docker project, image tags, container names, and volumes; record their state before changing them.
- [ ] Update the local APEX/ORDS Docker target to 26.2 while preserving the 26.1 volume and recovery data.
- [ ] Verify the running database/APEX/ORDS versions before switching the source branch.
- [ ] Switch to the current 26.2 template branch and read its `AGENTS.md`, project instructions, and known limitations.
- [ ] Run the 26.2 offline suite and target-appropriate smoke checks; diagnose and fix confirmed issues with focused regressions.
- [ ] Re-run the full 26.2 suite, check the diff, and record exact results without committing or pushing.
