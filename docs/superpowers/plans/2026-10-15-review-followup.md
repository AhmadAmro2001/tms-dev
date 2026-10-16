# APEX 26.1 implementation review follow-up

Spec: `docs/superpowers/specs/2026-10-15-confirmed-review-remediation.md`.
Base: `1985fed599f33c5248ee7360b4f8067697ad8a3c`.
Scope: repair R1–R5 from the inline implementation review. Existing F1–F9
fixes remain in scope for regression verification, without reimplementing them.

Constraints: existing branch and checkout; inline only; no database operations,
shared installation changes, commits or pushes. Preserve project-owned files.

### Task 1: Restore BOOLEAN and reject fractional metadata — R1, R4

- [x] Add positive BOOLEAN structure generation with an executable definition check.
- [x] Add malformed fractional/nonfinite precision, scale and length cases for
  both the formatter and generated definition checks. Keep integer compatibility.
- [x] Observe failing regressions, remove the BOOLEAN ban and share exact integer
  validation across generation and postconditions; run baseline/bundle modules.

Expected: valid BOOLEAN additions generate verified shape checks; malformed
numeric metadata raises BaselineError before SQL generation; tests pass.

### Task 2: Complete ASCII manifest whitespace — R5

- [x] Extend helper and Bash/PowerShell acceptance cases with form feed and
  vertical tab, and malformed non-ASCII whitespace cases.
- [x] Observe failures; split only supported LF/CRLF records and trim all ASCII
  whitespace at row/field boundaries; run manifest/backup CLI modules.

Expected: promised ASCII whitespace accepted, invalid manifests refused before
mirror replacement, old mirror bytes preserved; both-shell tests pass.

### Task 3: Strengthen receipt refusal evidence — R3

- [x] Use generated baseline column/view checks in the apply tests.
- [x] Assert actual status.dev.json absence, pending event and locked retry,
  retained failed-check evidence; demonstrate injected receipts fail assertions.
- [x] Run the migration CLI module with actual failed-check behavior.

Expected: definition/validity failure leaves no verified receipt and prevents
reuse; the regressions catch a wrongly written real receipt.

### Task 4: Document and exercise old-lock recovery — R2

- [x] Add local-Git fixtures for explicit historical TEAM-lock recovery,
  byte-preserving dry-run, successful source rewrite and custom-fork retention.
- [x] Document clean-tree dry-run/apply, source precedence and conflict handling
  in README and GETTING_STARTED; preserve default selection and refusal logic.
- [x] Run upgrade, documentation and manifest modules.

Expected: explicit recovery installs candidate files and records the chosen
source, dry-run changes no bytes, custom source stays selected without override.

### Task 5: Verify and record the result

- [x] Run full unittest discovery, Ruff, Python compileall, shell/parser syntax,
  example environment validation and git diff --check.
- [x] Review the final uncommitted diff inline. Reconcile review results and
  record outstanding live qualification explicitly; do not claim CI covered
  uncommitted changes or mark unavailable target qualification passed.

Expected: offline checks pass with explicit skip counts and evidence paths;
all five findings closed, database qualification still unexecuted.
