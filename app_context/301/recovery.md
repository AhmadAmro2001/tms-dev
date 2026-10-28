# Application 301: TMS - Recovery & Operational Procedures

## Export & Source Synchronization
- **Export from Live DEV**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts/team.ps1 export 301
  ```
  Refreshes the APEXlang source in `apps/TMS/301/` from shared Builder state.

- **Publish to Shared DEV**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts/team.ps1 publish 301 --env dev
  ```
  Applies local APEXlang files to shared DEV with drift detection and version stamping.

## Database Mirror Recovery & Refresh
- To refresh the read-only database object mirrors:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts/team.ps1 backup-db
  ```
  Mirrors DDL for all tables, views, packages, procedures, functions, triggers, and synonyms into `database/TMS/`.

## Timesheet Cache Maintenance
If timesheet totals or monthly reports become inconsistent after manual database punch adjustments or shift reassignments, invoke the batch cache recalculation procedure from SQLcl:
```sql
BEGIN
    TMS.TIME_SHEET_REPORT_PKG.POPULATE_MONTHLY_CACHE(
        P_YEAR        => '2026',
        P_MONTH       => '10',
        P_LOCATION_ID => NULL,    -- NULL recalculates all locations
        P_DEPARTMENT  => NULL,
        P_LOCATION    => NULL,
        P_PROJECT     => NULL,
        P_BATCH_SIZE  => 100
    );
    COMMIT;
END;
/
```

## Unmatched Punch Recovery
To trigger an immediate re-evaluation and matching of staged punches:
```sql
DECLARE
    l_result CLOB;
BEGIN
    TMS.TRANSACTION_API_PKG.SYNC_PUNCHES_JOB(
        p_lookback_hours => 72,
        p_limit          => 50000,
        p_result         => l_result
    );
    COMMIT;
END;
/
```

