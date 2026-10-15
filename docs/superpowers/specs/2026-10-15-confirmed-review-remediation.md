# APEX 26.1 confirmed-review remediation requirements

## Purpose and baseline

- Repair the nine defects confirmed in the 2026-10-15 inline review of `ash2osh/APEX_PROJECT_TEMPLATE_26_1` at `325b911e3c5bf3e0254ee457cd4170b184e1f35b`.
  - Local `main` was `297e84f8ea46d4fd124927cc744b909028a27334`, twelve commits behind. Implementation must start from the reviewed revision or reconcile any later upstream changes first.
  - Original evidence: `/home/ash/projects/APEX_PROJECT_TEMPLATE_26_1/scratch/review-2026-10-15/REVIEW.md`, with repro scripts, JSON results, SQLcl transcripts and CI logs beside it. Those ignored artifacts support the findings; the durable requirements are recorded here so the plan does not depend on scratch surviving.
  - Baseline verification: 1,356 local tests run, 32 skipped; exact-SHA Linux/Windows/macOS CI passed. Those results predate repairs and are not post-fix evidence.

## Constraints

- APEX 26.1 compatibility; do not introduce APEX 26.2 APIs or the 26.2 descriptor contract.
- Python >=3.10; operational code remains stdlib-only, with Graphify optional.
- Preserve Bash and Windows PowerShell 5.1/PowerShell 7 behavior.
- Execute inline, without subagents, using the existing checkout and a named branch; no new worktree.
- No database connections, writes, imports, exports, deployment, or shared Graphify installation changes are authorized by this planning request.
- No commits or pushes without an explicit user instruction.
- Preserve project-owned files, `.env`, app source, migrations, receipts and attempt evidence. Consult `docs/known-limitations.md` before changing behavior.
- Source files use LF. New internal helpers must be template-owned; these planning documents remain template-only under `docs/superpowers/**`.

## Required behavior

| Finding | Required result | Proof needed |
| --- | --- | --- |
| F1: malformed comment hides SQLcl directives | Rollout rejects `/*/` and the shared lexer’s client-parsing hazards before SQLcl starts, including through ORDS import. Valid quoted handler text and explicit rollout COMMIT/ROLLBACK remain accepted. | Lexer regression plus fake-runner assertion that execution was never invoked. |
| F2: rollout splits SQL at blank lines | Every rollout SQL driver sets SQLBLANKLINES ON before the payload include. | Generated-driver ordering test and disconnected SQLcl parser comparison. |
| F3: malformed backup manifests pass | One shared validator requires the exact type inventory and valid counts before either shell can install a mirror. Invalid evidence preserves every old mirror. | Shared parser matrix plus Bash/PowerShell wrapper tests with a committed old mirror and install spy. |
| F4: DBA settings rejected | All three config readers accept optional DEV/STAGING/PROD DBA aliases from `.env`, with matching validation and documented precedence. | Parser parity, file-over-ambient precedence, and supported-wrapper tests using fake SQLcl. |
| F5: wrong upgrade upstream | Fresh 26.1 projects use the 26.1 repository by default. Existing historical locks have an explicit, tested `--source` recovery route; custom upstreams are not silently changed. | Manifest/docs contract and upgrade integration fixtures for fresh, old-lock and custom-source cases. |
| F6: nullable additions have no checks | Every added column has a nonempty owner/table/column-scoped definition postcondition, even when nullable. | Nullable-only folder installs and validates; missing or wrong-shaped columns fail verification. |
| F7: numeric attributes lost | Preserve NUMBER precision/scale and FLOAT binary precision, or refuse unsupported/incomplete metadata; never silently broaden the type. | Formatter boundary tests plus generated DDL and metadata-check assertions. |
| F8: views checked only for existence | Every generated view has owner/name/type-scoped VALID and compilation-error postconditions, independently of stored-unit changes. | View-only generation regression and failed verification/no-receipt test; live behavior remains separately qualified. |
| F9: optional dependency typo | The graph extra uses `graphifyy` and resolves through ordinary project tooling. | Real dependency-resolution negative/positive control and an automated CI resolution gate. |

## Specific contracts

- **Backup manifest grammar:** UTF-8 without BOM; blank ASCII-whitespace lines may be ignored. Trim ASCII whitespace around each nonempty row and either side of exactly one `=`. Types are case-sensitive: tables requires exactly `TABLE`; code requires exactly `FUNCTION`, `PACKAGE`, `PACKAGE BODY`, `PROCEDURE`, `SYNONYM`, `TRIGGER`, `VIEW`. Every type appears once, including zero counts. Counts use ASCII digits only, interpreted base 10, in `0..9223372036854775807`; the sum must also fit that range. Reject unknown/duplicate/missing types, invalid rows, extra separators, signs, decimal/exponent forms and overflow. Accept LF/CRLF, a missing final newline, and leading zeroes. After parsing, compare the scope’s total with the existing scope-directory SQL-file total before mirror replacement.
- **DBA aliases:** optional single saved-connection aliases matching `[A-Za-z0-9][A-Za-z0-9._-]*`. File values override process values. Absent file keys preserve externally supplied aliases for compatibility; validate both channels. Explicit blank values are errors. Never borrow another environment’s alias. Existing same-database/container/schema/edition checks and read-only restrictions remain enforced.
- **Numeric columns:** NUMBER supports unconstrained form, precision `1..38`, scale `-84..127`, and a scale with unspecified precision using `NUMBER(*,s)`. FLOAT supports binary precision `1..126`. Reject Python boolean attribute values (`True`/`False`), fractions, nonfinite numbers, invalid ranges and malformed values. Preserve Oracle SQL `BOOLEAN` columns. Add-column verification checks the applicable captured precision/scale/length semantics, using null-safe dictionary predicates.
- **View checks:** check the exact generated target view in ALL_OBJECTS with STATUS='VALID' and no matching ATTRIBUTE='ERROR' row in ALL_ERRORS. Do not recompile unrelated units merely to repair F8, and do not weaken immutable-attempt or fresh-verification rules.

## Observations outside the defect list

- The behind local branch is an execution-preparation item, not a tenth defect. Preserve all local work when choosing the implementation branch.
- Missing `.env` and placeholder `PROJECT.md` are intentional template state. Do not create target configuration or invent business context.
- The 32 local skips consist of 24 Windows-specific, 3 native macOS, and 5 local PowerShell-launcher cases. Record remaining skips; do not equate them with executed checks.

## Completion standard

- Each F1–F9 has a regression that fails for the reviewed behavior and passes after its repair; the full local suite and relevant platform CI pass at the final candidate SHA.
- Re-run the original probes against candidate source and classify each original symptom as resolved, retained limitation, or still unknown. Update the review evidence without rewriting historical results as current proof.
- Offline implementation completion and live Oracle/APEX qualification are separate statuses. Live SQL/DDL/data behavior is not claimed until an explicitly authorized disposable target is identity-verified, exercised, independently read back and cleaned up.
