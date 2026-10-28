# Application 301: TMS - Subscriptions & Shared Components

## Theme & UI Templates
- **Current Theme**: Universal Theme (`@universal-theme`, Theme 42).
- **Global Page**: Page `0` (`p00000-global-page.apx`).
- **Icons**: Font APEX icons (`fa-user`, `fa-clock-o`, `fa-building`, `fa-users`, `fa-calendar`, `fa-bar-chart`, `fa-cog`, `fa-table`).

## Authentication & Authorization Schemes
- **Custom Authentication**: `tms-custom-auth` (`TMS_CUSTOM_AUTH`).
  - Auth Function: `AUTH_PKG.AUTHENTICATE`.
  - Post-Auth Procedure: Checks `AUTH_PKG.IS_PASSWORD_RESET_REQUIRED` and redirects to `p09999-login` with `CHANGE_PASSWORD` request if needed.
- **Authorization Scheme**: `tms-authenticated` (`TMS Authenticated`).
  - Evaluates `AUTH_PKG.is_authenticated`.

## Shared Navigation Lists
- **`navigation-menu`**:
  - Dynamically gated with PL/SQL expressions checking `AUTH_PKG.CAN_READ_SQL(...)` and `AUTH_PKG.HAS_ROLE(...)`.
- **`navigation-bar`**:
  - Contains user profile avatar link (`&APP_USER.`), separator, and sign-out URL (`&LOGOUT_URL.`).

## Plugins
- **APEX Office Print (AOP)**:
  - Dynamic Action: `ucApexOfficePrintAopConvertDa` (AOP Convert)
  - Dynamic Action: `ucApexOfficePrintAopDa` (AOP DA)
  - Dynamic Action: `ucApexOfficePrintAopModal` (AOP Modal)
  - Process: `ucApexOfficePrintAopProcess` (AOP Process)
- Bundled plugin files located under `shared-components/plugins/`.

## List of Values (LOVs)
Common LOVs defined in `shared-components/lovs.apx`:
- Status LOVs (active, inactive, archived)
- Event types (punch In, punch Out)
- Shift & rotation plan selectors
- Department, location, project, and grade selectors
- Leave & permission categories

