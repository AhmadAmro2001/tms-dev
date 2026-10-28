# Application 301: TMS (Time Management System) - Purpose

## High-Level Purpose
Application `301` is the central web interface for enterprise time, attendance, and workforce scheduling. It connects raw biometric punch events collected from physical hardware to employee schedules, calculates daily attendance status and overtime, records exceptions and leaves, and prepares verified monthly timesheets.

## User Personas & Access Roles
1. **System Administrator (Roles 1 & 2)**:
   - Full access across all locations and organization units.
   - Manages user accounts, credential issuance, role assignments, location scoping, and system audit logs.
   - Configures attendance devices, network parameters, and sync intervals.
2. **Attendance / HR Officer**:
   - Manages employee profiles, leaves, missions, trainings, and permissions.
   - Configures shifts, rotation plans, and holiday calendars.
   - Reviews unmatched punches, adjusts manual transactions, and handles attendance reconciliations.
3. **Location / Department Supervisor**:
   - Scoped strictly to permitted locations via `AUTH_PKG.can_access_location` and `:APP_USER_LOCATION_IDS`.
   - Reviews daily/monthly timesheets and absence reports for employees within their assigned physical sites.

## Functional Modules & Pages
- **Administration & Security**:
  - `p09999-login`: Custom credential authentication with mandatory password reset flow.
  - `p00060-users` / `p01124-user-form`: User provisioning, role selection, location assignments.
  - `p00002-archived-users`: Inactive/archived user oversight.
  - `p00061-logs`: System and audit log inspection.
- **Hardware & Device Transactions**:
  - `p00010-devices`, `p01125-device-form`, `p01126-device-form-view`: Hardware registry and telemetry.
  - `p00011-transactions`, `p01122-add-transaction`, `p01123-transaction-form`: Raw and manual punch entries.
  - `p00900-punch-monitor`: Real-time punch traffic monitor.
  - `p00901-unmatched-punches`: Unmatched punch reconciliation.
  - `p00902-transaction-source-audit`: Audit trail of punch sources.
- **Organization & Workforce**:
  - `p00020-departments`, `p00021-projects`, `p00022-locations`, `p01133-grade-form`: Reference hierarchy.
  - `p00030-employees`, `p01145-employee-form`, `p01148-employee-details`: Master employee records.
- **Scheduling & Rotation Plans**:
  - `p00040-rotation-plans`, `p01135-rotation-plan-form`, `p01136-rotation-day-form`: Multi-day repeating rotation schedules.
  - `p00041-shifts`, `p01134-shift-form`: Daily shift parameters (work intervals, grace windows, breaks).
  - `p01138-alternate-shift-form`: Temporary shift overrides.
  - `p00042-public-holidays`: Official company holidays.
  - `p00043-month-cut-dates`: Monthly cut-off dates controlling edit-lock boundaries.
- **Absences & Exception Tracking**:
  - `p00031-vacations` / `p00140-vacation-details`: Vacation requests.
  - `p00032-missions` / `p01149-mission-details`: Official travel/missions.
  - `p00033-trainings` / `p01150-training-details`: Training programs.
  - `p00034-permissions` / `p00143-permission-details`: Hourly departure/entry permissions.
  - `p00035-special-leaves`: Special leave types (sick leave, bereavement, etc.).
  - `p00036-approved-overtimes` / `p00147-approved-overtime-details`: Pre-approved overtime hours.
  - `p00050-absence`: Consolidated absence view.
- **Timesheets & Analytics**:
  - `p00051-timesheet-selection`: Monthly timesheet filter and employee picker.
  - `p00052-timesheet-detail`: Daily breakdown of attendance, hours worked, tardiness, and overtime.
  - `p00005-timesheet-test`: Sandbox/verification test harness for timesheet calculations.
  - `p00053-erc-devices-workload`: Device transaction workload analytics.
- **Data Import**:
  - `p00100-import-center`: Batch data import utility.

