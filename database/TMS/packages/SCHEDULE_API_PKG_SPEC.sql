
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."SCHEDULE_API_PKG" as
    /* Returns all shift definitions. */
    procedure get_shifts(p_rows out sys_refcursor);
    /* Returns rotation plans with their day-to-shift assignments. */
    procedure get_rotation_plans(p_rows out sys_refcursor);
    /* Returns rotation assignment history optionally filtered by employee. */
    procedure get_rotation_history(p_employee_id number, p_rows out sys_refcursor);
    /* Returns employee-specific alternate shifts within an optional date range. */
    procedure get_alternate_shifts(p_employee_id number, p_from date, p_to date, p_rows out sys_refcursor);
    /* Returns holidays overlapping an optional timestamp range. */
    procedure get_holidays(p_from timestamp, p_to timestamp, p_rows out sys_refcursor);
    /* Returns monthly timesheet cut dates optionally filtered by location. */
    procedure get_month_cut_dates(p_location_id number, p_rows out sys_refcursor);
    /* SCHEDULE_TYPE is SHIFT, ROTATION_PLAN, ROTATION_DAY, ROTATION_HISTORY,
       ALTERNATE_SHIFT, HOLIDAY, or MONTH_CUT_DATE. */
    procedure upsert_schedule(
        p_schedule_type varchar2, p_entity_id number, p_employee_id number,
        p_location_id number, p_name varchar2, p_from_date timestamp,
        p_to_date timestamp, p_value_1 varchar2, p_value_2 number,
        p_text_1 varchar2, p_text_2 varchar2, p_expected_version number, p_idempotency_key varchar2,
        p_result_id out number, p_status out varchar2, p_message out varchar2
    );
    procedure delete_schedule(
        p_schedule_type varchar2, p_entity_id number,
        p_status out varchar2, p_message out varchar2
    );
end SCHEDULE_API_PKG;
/
