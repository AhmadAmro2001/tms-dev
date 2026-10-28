# Application 301: TMS - Known Issues & Operational Considerations

## 1. Static Parser Limitation in `uc-apx` on Unquoted Hash `#`
- **Location**: `apps/TMS/301/pages/p00051-timesheet-selection.apx` (line 145).
- **Issue**: The property `columnFormatting.htmlExpression` contains an unquoted string with a URL anchor/token containing `#`:
  ```apexlang
  htmlExpression: <a href="#DETAIL_URL!ATTR#" class="t-Button t-Button--noLabel ...
  ```
- **Behavior**: The official APEX APEXlang exporter emitted this string unquoted. However, the static parser in `uc-apx v26.1` parses `#` as a comment delimiter when unquoted, failing parsing with `unexpected character '#' after ''`.
- **Note**: Hand-quoting the string if editing `p00051` resolves the parse in `uc-apx`, but subsequent official re-exports from APEX Builder may re-emit unquoted strings.

## 2. Monthly Edit Locking via `MONTH_CUT_DATE`
- Edits to historical attendance, shifts, or leaves for a closed payroll period are constrained by `AUTH_PKG.is_month_open(p_work_date, p_location_id)`.
- If an attendance officer attempts to modify past records after the cut date has passed, the transaction is rejected unless an administrative cut-date extension is granted.

## 3. High-Volume Timesheet Caching (`TIME_SHEET_CACHE`)
- Real-time pipelined calculation across hundreds of employees over a 31-day period involves extensive shift matching, punch aggregation, and exception joins.
- The system uses `TIME_SHEET_CACHE` populated via `TIME_SHEET_REPORT_PKG.POPULATE_MONTHLY_CACHE`. If monthly summaries appear outdated after punch adjustments, the monthly cache must be refreshed.

## 4. Unmatched Punches from External Biometric Terminals
- Biometric terminals ingest punches by numeric badge number. If a new employee badge is swiped before the employee record is created in `EMPLOYEE`, punches are routed to `TRANSACTION_STAGE` and flagged as unmatched.
- These require resolution via `p00901-unmatched-punches` to associate the badge with the correct employee ID.

