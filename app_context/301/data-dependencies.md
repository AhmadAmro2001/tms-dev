# Application 301: TMS - Data Dependencies & Architecture

## Parsing Schema & Targets
- **Parsing Schema**: `TMS`
- **Application ID**: `301`
- **Database Version Target**: Oracle Database 23ai (`23.26.1.0.0`, COMPATIBLE `23.6.0`).

## Core Database Tables

| Table Name | Purpose | Primary Keys & Key Relations |
|---|---|---|
| `EMPLOYEE` | Master employee records | `ID` (PK), FKs to `DEPARTMENT`, `PROJECT`, `LOCATION`, `GRADE` |
| `DEPARTMENT`, `PROJECT`, `LOCATION`, `GRADE` | Organizational master data | Referenced by `EMPLOYEE` |
| `DEVICE` | Biometric attendance terminals | `ID` (PK), `LOCATION_ID`, IP, Port, Comm Key |
| `TRANSACTION` | Attendance punches | `ID` (PK), `EMPLOYEE_ID`, `DEVICE_ID`, `PUNCH_TIME`, `EVENT_TYPE` |
| `TRANSACTION_STAGE` | Raw punch import staging | Batch import and validation buffer |
| `SHIFT` | Shift definitions | `ID` (PK), start/end times, grace periods |
| `ROTATION_PLAN`, `ROTATION_DAY` | Repeating rotation cycles | `PLAN_ID`, day offsets mapping to `SHIFT_ID` |
| `ROTATION_HISTORY` | Shift plan assignments to employees | `EMPLOYEE_ID`, `PLAN_ID`, effective date range |
| `ALTERNATE_SHIFT` | Employee temporary shift overrides | `EMPLOYEE_ID`, `WORK_DATE`, `SHIFT_ID` |
| `OFFICIAL_HOLIDAY` | Public/company holidays | Holiday date range, description |
| `MONTH_CUT_DATE` | Payroll cut-off dates by location | `LOCATION_ID`, `YEAR_MONTH`, cut-off date |
| `VACATION`, `PERMISSION`, `MISSION`, `TRAINING`, `SPECIAL_LEAVE` | Absence and leave records | `EMPLOYEE_ID`, date ranges, approval status |
| `APPROVED_OVERTIME` | Pre-approved overtime hours | `EMPLOYEE_ID`, `OVERTIME_DATE`, hours approved |
| `TIME_SHEET_CACHE` | Cached monthly timesheet calculations | `EMPLOYEE_ID`, `YEAR`, `MONTH`, daily hour breakdowns |
| `APP_USER`, `USER_ACCOUNT` | Application users and credentials | `ID` (PK), username, status |
| `APP_USER_LOCATION` | User-to-location mapping for RLS | `APP_USER_ID`, `LOCATION_ID` |
| `APP_ROLE`, `APP_USER_ROLE`, `APP_ROLE_FEATURE` | Role-based feature permissions | `ROLE_ID`, `FEATURE_ID` |
| `WRITE_IDEMPOTENCY` | Prevents duplicate transactional POSTs | `OPERATION_CODE`, `IDEMPOTENCY_KEY` |
| `AOP_*` | APEX Office Print metadata & templates | Document generation configurations |

## Database Views
- `V_DASHBOARD_SUMMARY`: High-level attendance metrics for home dashboard.
- `V_EMPLOYEE`: Enriched employee details with organization descriptions.
- `V_EMPLOYEE_TIMESHEET`: Daily timesheet summary join.
- `V_EMPLOYEE_TRANSACTION_SUMMARY`: Punch counts and first-in/last-out calculations.
- `V_DEVICE_ACTIVITY`: Activity timestamp tracking per terminal.
- `V_PUNCH_EMPLOYEE_MATCH`: Resolution of raw punch badge numbers to employee records.
- `V_UNMATCHED_PUNCH`: Punch events without a corresponding active employee record.

## PL/SQL API Packages
- **`AUTH_PKG`**: Manages authentication, session validation, password reset enforcement, role checks (`HAS_ROLE`), feature permissions (`CAN_READ_SQL`, `CAN_WRITE_SQL`), and location scoping (`can_access_location`, `accessible_location_ids_csv`).
- **`TRANSACTION_API_PKG`**: Handles punch queries, staging, manual punches, and automated background sync jobs (`sync_punches_job`).
- **`TIMESHEET_API_PKG`**: Provides employee daily timesheet summaries, absence feeds, and alternate shift overrides.
- **`TIME_SHEET_REPORT_PKG`**: Pipelined report functions (`GET_TIME_SHEET_REPORT_APEX`) and batch cache calculation (`POPULATE_MONTHLY_CACHE`).
- **`SCHEDULE_API_PKG`**: CRUD APIs for shifts, rotation plans, calendar holidays, and month cut-off dates.
- **`DEVICE_API_PKG`**: Device registry, command queueing, and connection telemetry.
- **`EVENT_API_PKG`**: Event/exception processing for vacations, permissions, missions, trainings, and overtime.

## Security & Session State Binding
- **Application Item `:APP_USER_LOCATION_IDS`**:
  Populated on page load via application process `Cache User Location IDs` calling `AUTH_PKG.accessible_location_ids_csv`. Used across reports to filter `LOCATION_ID in (select column_value from table(apex_string.split(:APP_USER_LOCATION_IDS, ':')))` avoiding per-row function overhead.
- **Idempotency Guard**:
  All modifying procedures accept an `idempotency_key` and record completion in `WRITE_IDEMPOTENCY` to prevent duplicate submissions.

