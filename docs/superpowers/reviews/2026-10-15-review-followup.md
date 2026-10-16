# APEX 26.1 review follow-up result

## Scope and state

- Base commit: `1985fed599f33c5248ee7360b4f8067697ad8a3c` on
  `codex/fix-26-1-review-findings`. The follow-up was verified as working-tree
  changes before the user authorized its commit and push.
- All five implementation-review findings are closed with focused regressions
  and a passing full offline suite: 1,403 tests run, 32 skipped, exit 0.
- This record covers the offline implementation phase, performed inline without
  subagents or database operations. The user subsequently requested commit,
  push and a separate agy CLI live-verification phase. Its local evidence belongs
  under `scratch/live-qualification-2026-10-15/`; this offline record does not
  claim its results. No shared Graphify installation or remote upgrade was used.

## Finding closure

| Finding | Correction | Verification |
| --- | --- | --- |
| R1: SQL BOOLEAN rejected | Removed the datatype ban while keeping Python boolean metadata invalid. | Structure fixture emits BOOLEAN addition; generated check passes only for the correct owner/table/column/type and fails for missing/wrong rows. |
| R2: historical lock recovery missing | Added explicit-source recovery instructions to README and GETTING_STARTED; retained source precedence and schema-version refusal. | Real local-Git/CLI fixtures reproduce incompatible TEAM refusal, recover via the explicit 26.1 URL, preserve all bytes on dry-run, update lock source/commit on apply, preserve conflicts and retain a chosen fork. Network protocols are forbidden in the public-URL fixture. |
| R3: receipt tests checked wrong file | Tests now inspect status.dev.json, generated checks, failed-check evidence, pending events, locked state and retry writes. | Normal migration tests pass; injecting a real verified receipt makes both repaired tests fail, whereas both previously passed the same mutation. |
| R4: numeric metadata truncated | Shared exact-integer validation is used by type formatting and definition checks for precision, scale and lengths. | Fractional and nonfinite float/Decimal inputs raise BaselineError; existing integer/string and exactly integral float/Decimal representations pass. |
| R5: incomplete ASCII whitespace | Split manifest records on LF and trim the full ASCII whitespace set at field boundaries. | Form feed, vertical tab, spaces, tabs and CRLF pass; Unicode separators are refused; both-shell wrapper tests prove malformed evidence preserves the old mirror and never calls replacement. |

## Verification evidence

- Focused modules: baseline and bundle 68 tests; manifest and backup CLI 23;
  migration CLI 42; upgrade/documentation/manifest 90. All passed.
- Full discovery: `python3 -m unittest discover -s tests -v` ran 1,403 tests
  in 425.961 seconds, exit 0, `OK (skipped=32)`. Skips comprise 24 Windows-only,
  3 native macOS qualification and 5 local snap-PowerShell launcher cases.
- Ruff, Python compileall, Bash syntax for all shell scripts, PowerShell parser
  syntax for all PowerShell scripts, example environment loading, application
  JSON validation, tracked/new source line endings and `git diff --check` passed.
- Ignored local evidence is under
  `.superpowers/sdd/2026-10-15-review-followup/`: `task-1-red.log`,
  `task-2-red.log`, `task-1-tests.log` through `task-5-tests.log`,
  `task-3-before.json`, `task-3-after.json`, and `progress.md`.
- The original review is historical evidence at
  `scratch/review-implementation-1985fed/REVIEW.md`; this result supersedes its
  open R1–R5 status for the verified follow-up changes.

## Limits and integration

- This is offline qualification with real local Git fixtures and fake database
  sessions. Root `.env` is absent. Live NUMBER/FLOAT dictionary round-trips,
  connected SQLcl execution, invalid-view compilation/read-back and disposable
  target cleanup remain unexecuted. No live result is claimed.
- At offline verification time, native Windows and macOS CI had passed for the
  base commit only. Exact follow-up commit CI must be checked after its push.
  The local suite records its platform skips explicitly.
- The final diff receives an inline self-review because the user requested no
  subagents. That review found no additional defects. No independent reviewer
  or merge approval is claimed; no review findings were deferred.
- The original plan's unchecked boxes are retained as historical acceptance
  criteria; this result and the follow-up checklist report current progress.
