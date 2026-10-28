
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."EVENT_API_PKG" as
    /* Returns structured audit events within an optional range and event-code filter. */
    procedure get_audit_events(
        p_from timestamp, p_to timestamp, p_event_code varchar2, p_rows out sys_refcursor
    );
    /* Returns vacation rows; the JSON filter contract is reserved for page filters. */
    procedure get_vacations(p_filters_json clob, p_rows out sys_refcursor);
    /* Returns mission rows; the JSON filter contract is reserved for page filters. */
    procedure get_missions(p_filters_json clob, p_rows out sys_refcursor);
    /* Returns training rows; the JSON filter contract is reserved for page filters. */
    procedure get_trainings(p_filters_json clob, p_rows out sys_refcursor);
    /* Returns permission rows; the JSON filter contract is reserved for page filters. */
    procedure get_permissions(p_filters_json clob, p_rows out sys_refcursor);
    /* Returns approved overtime rows; the JSON filter contract is reserved for page filters. */
    procedure get_approved_overtime(p_filters_json clob, p_rows out sys_refcursor);
    /* EVENT_TYPE is VACATION, MISSION, TRAINING, PERMISSION, SPECIAL_LEAVE, or APPROVED_OVERTIME. */
    procedure upsert_event(
        p_event_type varchar2, p_entity_id number, p_employee_id number,
        p_from_date timestamp, p_to_date timestamp, p_type_id number,
        p_description varchar2, p_expected_version number, p_idempotency_key varchar2,
        p_result_id out number, p_status out varchar2, p_message out varchar2
    );
    procedure delete_event(
        p_event_type varchar2, p_entity_id number,
        p_status out varchar2, p_message out varchar2
    );
    procedure upsert_vacation(
        p_vacation_id number, p_employee_id number, p_from_date timestamp,
        p_to_date timestamp, p_type_id number, p_idempotency_key varchar2,
        p_entity_id out number, p_status out varchar2, p_message out varchar2
    );
end EVENT_API_PKG;
/
