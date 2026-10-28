
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."REFERENCE_API_PKG" as
    /* Returns locations filtered by ID when supplied. */
    procedure get_locations(p_location_id number, p_rows out sys_refcursor);
    /* Returns employees filtered by their business employee number. */
    procedure get_employees(p_employee_number varchar2, p_rows out sys_refcursor);
    /* REFERENCE_TYPE is DEPARTMENT, PROJECT, LOCATION, GRADE, or EMPLOYEE. */
    procedure upsert_reference(
        p_reference_type varchar2, p_entity_id number, p_name varchar2,
        p_employee_number number, p_project_id number, p_location_id number,
        p_department_id number, p_grade_id number, p_is_active char,
        p_nationality varchar2, p_religion varchar2, p_print_timesheet char,
        p_expected_version number, p_idempotency_key varchar2, p_result_id out number,
        p_status out varchar2, p_message out varchar2
    );
    procedure delete_reference(
        p_reference_type varchar2, p_entity_id number,
        p_status out varchar2, p_message out varchar2
    );
end REFERENCE_API_PKG;
/
