
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."REFERENCE_API_PKG" as
    procedure get_locations(p_location_id number, p_rows out sys_refcursor) is
    begin
        open p_rows for select ID, NAME from V_LOCATION
        where (p_location_id is null or ID = p_location_id)
          and AUTH_PKG.can_access_location_sql(ID) = 1
        order by NAME;
    end get_locations;

    procedure get_employees(p_employee_number varchar2, p_rows out sys_refcursor) is
    begin
        open p_rows for select ID, EMPLOYEE_NUMBER, NAME, LOCATION_ID, DEPARTMENT_ID, PROJECT_ID
        from V_EMPLOYEE
        where (p_employee_number is null or to_char(EMPLOYEE_NUMBER) = p_employee_number)
          and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1
        order by EMPLOYEE_NUMBER;
    end get_employees;

    procedure require_reference_administrator(p_reference_type varchar2) is
        l_type varchar2(30) := upper(trim(p_reference_type));
    begin
        if not (AUTH_PKG.has_role('1') or AUTH_PKG.has_role('2')) then
            raise_application_error(-20200, 'Reference administration requires role 1 or 2');
        end if;
        if l_type in ('LOCATION', 'PROJECT', 'GRADE') and not AUTH_PKG.has_role('1') then
            raise_application_error(-20201, l_type || ' administration requires role 1');
        end if;
        if l_type = 'EMPLOYEE' and not AUTH_PKG.can_write('WriteEmployees')
           and not AUTH_PKG.has_role('1') and not AUTH_PKG.has_role('2') then
            raise_application_error(-20202, 'Employee write access is not granted');
        end if;
    end require_reference_administrator;

    procedure rejected(p_operation varchar2, p_entity_type varchar2, p_entity_id number,
                       p_error varchar2, p_key varchar2, p_status out varchar2,
                       p_message out varchar2) is
    begin
        rollback;
        p_status := 'REJECTED'; p_message := substr(p_error, 1, 4000);
        AUDIT_PKG.record_rejection(p_operation, p_entity_type, p_entity_id, p_message, p_key);
    end rejected;

    procedure require_reference(p_table_name varchar2, p_id number, p_label varchar2) is
        l_count number;
    begin
        if p_id is null then return; end if;
        if p_table_name = 'PROJECT' then select count(*) into l_count from PROJECT where ID = p_id;
        elsif p_table_name = 'LOCATION' then select count(*) into l_count from LOCATION where ID = p_id;
        elsif p_table_name = 'DEPARTMENT' then select count(*) into l_count from DEPARTMENT where ID = p_id;
        else select count(*) into l_count from GRADE where ID = p_id;
        end if;
        if l_count <> 1 then raise_application_error(-20203, p_label || ' was not found'); end if;
    end require_reference;

    procedure upsert_reference(
        p_reference_type varchar2, p_entity_id number, p_name varchar2,
        p_employee_number number, p_project_id number, p_location_id number,
        p_department_id number, p_grade_id number, p_is_active char,
        p_nationality varchar2, p_religion varchar2, p_print_timesheet char,
        p_expected_version number, p_idempotency_key varchar2, p_result_id out number,
        p_status out varchar2, p_message out varchar2
    ) is
        l_type varchar2(30) := upper(trim(p_reference_type));
        l_existing_id number;
        l_retry boolean;
        l_existing_location_id number;
        l_count number;
        l_audit_details clob;
    begin
        require_reference_administrator(l_type);
        if l_type not in ('DEPARTMENT', 'PROJECT', 'LOCATION', 'GRADE', 'EMPLOYEE')
           or p_idempotency_key is null then
            raise_application_error(-20204, 'Supported reference type and idempotency key are required');
        end if;
        if l_type <> 'EMPLOYEE' and (trim(p_name) is null or length(trim(p_name)) not between 3 and 50) then
            raise_application_error(-20205, 'Reference name must be 3 to 50 characters');
        end if;
        if l_type = 'EMPLOYEE' then
            if p_employee_number is null or trim(p_name) is null or length(trim(p_name)) not between 3 and 50
               or p_location_id is null then
                raise_application_error(-20206, 'Employee number, name (3-50), and location are required');
            end if;
            require_reference('PROJECT', p_project_id, 'Project');
            require_reference('LOCATION', p_location_id, 'Location');
            require_reference('DEPARTMENT', p_department_id, 'Department');
            require_reference('GRADE', p_grade_id, 'Grade');
            if not AUTH_PKG.can_access_location(p_location_id) then
                raise_application_error(-20207, 'Employee location is out of scope');
            end if;
            if p_entity_id is not null then
                select LOCATION_ID into l_existing_location_id from EMPLOYEE where ID = p_entity_id for update;
                if not AUTH_PKG.can_access_location(l_existing_location_id) then
                    raise_application_error(-20208, 'Existing employee is out of scope');
                end if;
            end if;
            select count(*) into l_count from EMPLOYEE
             where EMPLOYEE_NUMBER = p_employee_number and ID <> nvl(p_entity_id, -1);
            if l_count > 0 then raise_application_error(-20209, 'Employee number already exists'); end if;
        end if;
        AUDIT_PKG.reserve_idempotency('REFERENCE_' || l_type || '_UPSERT', p_idempotency_key,
                                      l_type, l_existing_id, l_retry);
        if l_retry then p_result_id := l_existing_id; p_status := 'IDEMPOTENT';
            p_message := 'Existing reference request was returned'; return; end if;
        if l_type = 'DEPARTMENT' then
            if p_entity_id is null then insert into DEPARTMENT (NAME) values (trim(p_name)) returning ID into p_result_id;
            else update DEPARTMENT set NAME = trim(p_name) where ID = p_entity_id and ORA_ROWSCN = p_expected_version; if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: department changed'); end if; p_result_id := p_entity_id; end if;
        elsif l_type = 'PROJECT' then
            if p_entity_id is null then insert into PROJECT (NAME) values (trim(p_name)) returning ID into p_result_id;
            else update PROJECT set NAME = trim(p_name) where ID = p_entity_id and ORA_ROWSCN = p_expected_version; if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: project changed'); end if; p_result_id := p_entity_id; end if;
        elsif l_type = 'LOCATION' then
            if p_entity_id is null then insert into LOCATION (NAME) values (trim(p_name)) returning ID into p_result_id;
            else update LOCATION set NAME = trim(p_name) where ID = p_entity_id and ORA_ROWSCN = p_expected_version; if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: location changed'); end if; p_result_id := p_entity_id; end if;
        elsif l_type = 'GRADE' then
            if p_entity_id is null then insert into GRADE (NAME) values (trim(p_name)) returning ID into p_result_id;
            else update GRADE set NAME = trim(p_name) where ID = p_entity_id and ORA_ROWSCN = p_expected_version; if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: grade changed'); end if; p_result_id := p_entity_id; end if;
        else
            if p_entity_id is null then
                insert into EMPLOYEE (EMPLOYEE_NUMBER, NAME, PROJECT_ID, LOCATION_ID, DEPARTMENT_ID,
                                      IS_ACTIVE, GRADE_ID, NATIONALITY, RELIGION, PRINT_TIMESHEET, CREATION_DATE)
                values (p_employee_number, trim(p_name), p_project_id, p_location_id, p_department_id,
                        case when upper(nvl(p_is_active, 'Y')) in ('Y', '1') then '1' else '0' end,
                        p_grade_id, p_nationality, p_religion,
                        case when upper(nvl(p_print_timesheet, 'Y')) in ('Y', '1') then '1' else '0' end,
                        systimestamp)
                returning ID into p_result_id;
            else
                update EMPLOYEE
                   set EMPLOYEE_NUMBER = p_employee_number, NAME = trim(p_name), PROJECT_ID = p_project_id,
                       LOCATION_ID = p_location_id, DEPARTMENT_ID = p_department_id,
                       IS_ACTIVE = case when upper(nvl(p_is_active, 'Y')) in ('Y', '1') then '1' else '0' end,
                       GRADE_ID = p_grade_id, NATIONALITY = p_nationality, RELIGION = p_religion,
                       PRINT_TIMESHEET = case when upper(nvl(p_print_timesheet, 'Y')) in ('Y', '1') then '1' else '0' end,
                       LAST_UPDATE_DATE = systimestamp
                 where ID = p_entity_id and ORA_ROWSCN = p_expected_version;
                if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: employee changed'); end if;
                p_result_id := p_entity_id;
            end if;
        end if;
        if p_entity_id is not null and sql%rowcount <> 1 then
            raise_application_error(-20210, 'Reference row was not found');
        end if;
        select json_object('idempotency_key' value p_idempotency_key returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('REFERENCE_' || l_type || '_UPSERT', l_type, p_result_id, l_audit_details);
        AUDIT_PKG.complete_idempotency('REFERENCE_' || l_type || '_UPSERT', p_idempotency_key, p_result_id);
        commit; p_status := 'SUCCESS'; p_message := 'Reference saved';
    exception when others then
        if sqlcode = -20901 then rollback; p_status := 'CONFLICT'; p_message := substr(sqlerrm, 1, 4000);
        else rejected('REFERENCE_' || nvl(l_type, 'UNKNOWN') || '_UPSERT', nvl(l_type, 'REFERENCE'),
                 p_entity_id, sqlerrm, p_idempotency_key, p_status, p_message); end if;
    end upsert_reference;

    procedure delete_reference(
        p_reference_type varchar2, p_entity_id number,
        p_status out varchar2, p_message out varchar2
    ) is
        l_type varchar2(30) := upper(trim(p_reference_type));
        l_dependencies number;
        l_existing_location_id number;
    begin
        require_reference_administrator(l_type);
        if p_entity_id is null or l_type not in ('DEPARTMENT', 'PROJECT', 'LOCATION', 'GRADE', 'EMPLOYEE') then
            raise_application_error(-20211, 'Supported reference type and identifier are required');
        end if;
        if l_type = 'DEPARTMENT' then
            select count(*) into l_dependencies from EMPLOYEE where DEPARTMENT_ID = p_entity_id;
            if l_dependencies > 0 then raise_application_error(-20212, 'Department is used by employees and cannot be deleted'); end if;
            delete from DEPARTMENT where ID = p_entity_id;
        elsif l_type = 'PROJECT' then
            select count(*) into l_dependencies from EMPLOYEE where PROJECT_ID = p_entity_id;
            if l_dependencies > 0 then raise_application_error(-20213, 'Project is used by employees and cannot be deleted'); end if;
            delete from PROJECT where ID = p_entity_id;
        elsif l_type = 'LOCATION' then
            select count(*) into l_dependencies from EMPLOYEE where LOCATION_ID = p_entity_id;
            if l_dependencies > 0 then raise_application_error(-20214, 'Location is used by employees and cannot be deleted'); end if;
            delete from LOCATION where ID = p_entity_id;
        elsif l_type = 'GRADE' then
            select count(*) into l_dependencies from EMPLOYEE where GRADE_ID = p_entity_id;
            if l_dependencies > 0 then raise_application_error(-20215, 'Grade is used by employees and cannot be deleted'); end if;
            delete from GRADE where ID = p_entity_id;
        else
            select LOCATION_ID into l_existing_location_id from EMPLOYEE where ID = p_entity_id for update;
            if not AUTH_PKG.can_access_location(l_existing_location_id) then raise_application_error(-20216, 'Employee is out of scope'); end if;
            delete from EMPLOYEE where ID = p_entity_id;
        end if;
        if sql%rowcount <> 1 then raise_application_error(-20217, 'Reference row was not found'); end if;
        AUDIT_PKG.record_event('REFERENCE_' || l_type || '_DELETE', l_type, p_entity_id, null);
        commit; p_status := 'SUCCESS'; p_message := 'Reference deleted';
    exception when others then
        rejected('REFERENCE_' || nvl(l_type, 'UNKNOWN') || '_DELETE', nvl(l_type, 'REFERENCE'),
                 p_entity_id, sqlerrm, null, p_status, p_message);
    end delete_reference;
end REFERENCE_API_PKG;
/
