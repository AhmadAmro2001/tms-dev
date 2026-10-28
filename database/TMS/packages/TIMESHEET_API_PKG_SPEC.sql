
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."TIMESHEET_API_PKG" as
    /* Returns daily employee attendance summaries for a date range. */
    procedure get_timesheet(
        p_employee_id number, p_from timestamp, p_to timestamp, p_rows out sys_refcursor
    );
    /* Returns vacation, mission, and training rows as a common absence feed. */
    procedure get_absence(
        p_employee_id number, p_from timestamp, p_to timestamp, p_rows out sys_refcursor
    );
    /* Returns daily summaries where an in or out transaction is incomplete. */
    procedure get_incomplete_hours(p_from timestamp, p_to timestamp, p_rows out sys_refcursor);
    /* Returns transaction counts and date ranges grouped by device. */
    procedure get_device_workload(p_from timestamp, p_to timestamp, p_rows out sys_refcursor);
    procedure upsert_alternate_shift(
        p_employee_id number, p_work_date date, p_shift_id number,
        p_idempotency_key varchar2, p_entity_id out number,
        p_status out varchar2, p_message out varchar2
    );
    /* The versioned overload prevents a stale timesheet detail page from overwriting an override. */
    procedure upsert_alternate_shift(
        p_employee_id number, p_work_date date, p_shift_id number,
        p_expected_version number, p_idempotency_key varchar2, p_entity_id out number,
        p_status out varchar2, p_message out varchar2
    );
    procedure record_print_decision(
        p_employee_id number, p_month date, p_decision varchar2,
        p_idempotency_key varchar2, p_status out varchar2, p_message out varchar2
    );
end TIMESHEET_API_PKG;
/
