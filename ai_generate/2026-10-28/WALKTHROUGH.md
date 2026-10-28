# 2026-10-28 — Rotation plan shifts by day

- Page 1135 now uses a required numeric day count and provides one shift selector per configured day, up to 30. Selectors show and clear as the day count changes, and existing plan assignments load into their matching selectors.
- Saving validates each selected shift, updates or inserts the matching `ROTATION_DAY` rows through `SCHEDULE_API_PKG`, and removes assignments beyond a reduced day count.
- This pass changed APEXlang source only. The package and database migration remain unchanged. The existing package commits each upsert separately, so the save is not all-or-nothing until the package migration is available.
- `uc-apx validate` and `uc-apx validate --official` passed for an isolated copy of page 1135 with its shared components. Whole-app validation still stops on parser errors in existing pages 51 and 52.
