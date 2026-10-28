
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."TIMESHEET_API_PKG" as
    procedure require_edit_access(p_employee_id number, p_work_date date) is
        l_location_id number;
    begin
        if not (AUTH_PKG.has_role('1') or AUTH_PKG.has_role('2')) then
            raise_application_error(-20190, 'Timesheet edits require role 1 or 2');
        end if;
        select LOCATION_ID into l_location_id from EMPLOYEE where ID = p_employee_id and IS_ACTIVE = '1';
        if not AUTH_PKG.can_access_location(l_location_id)
           or not AUTH_PKG.is_month_open(p_work_date, l_location_id) then
            raise_application_error(-20191, 'Employee location is out of scope or closed for the work date');
        end if;
    end require_edit_access;

    procedure rejected(p_operation varchar2, p_entity_type varchar2, p_entity_id number,
                       p_error varchar2, p_key varchar2, p_status out varchar2,
                       p_message out varchar2) is
    begin
        rollback; p_status := 'REJECTED'; p_message := substr(p_error, 1, 4000);
        AUDIT_PKG.record_rejection(p_operation, p_entity_type, p_entity_id, p_message, p_key);
    end rejected;

    procedure get_timesheet(
        p_employee_id number, p_from timestamp, p_to timestamp, p_rows out sys_refcursor
    ) is
    begin
        open p_rows for
             select *
              from V_EMPLOYEE_TIMESHEET
             where (p_employee_id is null or EMPLOYEE_ID = p_employee_id)
               and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1
               and (p_from is null or WORK_DATE >= trunc(p_from))
               and (p_to is null or WORK_DATE < trunc(p_to))
             order by WORK_DATE desc nulls last, EMPLOYEE_NUMBER;
    end get_timesheet;

    procedure get_absence(
        p_employee_id number, p_from timestamp, p_to timestamp, p_rows out sys_refcursor
    ) is
    begin
        open p_rows for
            select 'VACATION' as ABSENCE_TYPE, v.ID, v.EMPLOYEE_ID, v.FROM_DATE, v.TO_DATE,
                   v.TYPE_ID, cast(null as varchar2(4000)) as DESCRIPTION
             from VACATION v
             join EMPLOYEE e on e.ID = v.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
               and (p_employee_id is null or v.EMPLOYEE_ID = p_employee_id)
               and (p_from is null or v.TO_DATE >= p_from)
               and (p_to is null or v.FROM_DATE < p_to)
            union all
            select 'MISSION', m.ID, m.EMPLOYEE_ID, m.FROM_DATE, m.TO_DATE,
                   cast(null as number), m.DESCRIPTION
             from MISSION m
             join EMPLOYEE e on e.ID = m.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
               and (p_employee_id is null or m.EMPLOYEE_ID = p_employee_id)
               and (p_from is null or m.TO_DATE >= p_from)
               and (p_to is null or m.FROM_DATE < p_to)
            union all
            select 'TRAINING', t.ID, t.EMPLOYEE_ID, t.FROM_DATE, t.TO_DATE,
                   cast(null as number), t.DESCRIPTION
             from TRAINING t
             join EMPLOYEE e on e.ID = t.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
               and (p_employee_id is null or t.EMPLOYEE_ID = p_employee_id)
               and (p_from is null or t.TO_DATE >= p_from)
               and (p_to is null or t.FROM_DATE < p_to)
             order by FROM_DATE, ID;
    end get_absence;

    procedure get_incomplete_hours(p_from timestamp, p_to timestamp, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select EMPLOYEE_ID, EMPLOYEE_NUMBER, EMPLOYEE_NAME, WORK_DATE,
                   ACTUAL_IN, ACTUAL_OUT, STANDARD_HOURS, IS_ABSENT, REMARKS,
                   CALCULATION_STATUS
              from V_EMPLOYEE_TIMESHEET
             where WORK_DATE is not null
               and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1
               and (p_from is null or WORK_DATE >= trunc(p_from))
               and (p_to is null or WORK_DATE < trunc(p_to))
               and IS_ABSENT = 'Y'
               and STANDARD_HOURS is not null
             order by WORK_DATE desc, EMPLOYEE_NUMBER;
    end get_incomplete_hours;

    procedure get_device_workload(p_from timestamp, p_to timestamp, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select d.ID as DEVICE_ID, d.NAME as DEVICE_NAME, d.LOCATION_ID,
                   count(t.ID) as TRANSACTION_COUNT,
                   min(t."DATE") as FIRST_TRANSACTION, max(t."DATE") as LAST_TRANSACTION
              from DEVICE d
              left join "TRANSACTION" t on t.DEVICE_ID = d.ID
             and (p_from is null or t."DATE" >= p_from)
             and (p_to is null or t."DATE" < p_to)
             group by d.ID, d.NAME, d.LOCATION_ID
             order by TRANSACTION_COUNT desc, d.NAME;
    end get_device_workload;

    procedure upsert_alternate_shift(
        p_employee_id number, p_work_date date, p_shift_id number,
        p_idempotency_key varchar2, p_entity_id out number,
        p_status out varchar2, p_message out varchar2
    ) is
    begin
        upsert_alternate_shift(p_employee_id, p_work_date, p_shift_id, null,
            p_idempotency_key, p_entity_id, p_status, p_message);
    end upsert_alternate_shift;

    procedure upsert_alternate_shift(
        p_employee_id number, p_work_date date, p_shift_id number,
        p_expected_version number, p_idempotency_key varchar2, p_entity_id out number,
        p_status out varchar2, p_message out varchar2
    ) is
        l_existing_id number;
        l_count number;
        l_retry boolean;
        l_audit_details clob;
    begin
        if p_employee_id is null or p_work_date is null or p_shift_id is null or p_idempotency_key is null then
            raise_application_error(-20192, 'Employee, work date, shift, and idempotency key are required');
        end if;
        require_edit_access(p_employee_id, p_work_date);
        select count(*) into l_count from SHIFT where ID = p_shift_id;
        if l_count <> 1 then raise_application_error(-20193, 'Shift was not found'); end if;
        AUDIT_PKG.reserve_idempotency('TIMESHEET_ALTERNATE_SHIFT',p_idempotency_key,'ALTERNATE_SHIFT',l_existing_id,l_retry);
        if l_retry then p_entity_id:=l_existing_id; p_status:='IDEMPOTENT'; p_message:='Existing alternate shift was returned'; return; end if;
        begin
            select ID into p_entity_id from ALTERNATE_SHIFT
             where EMPLOYEE_ID=p_employee_id and trunc("DATE")=trunc(p_work_date) for update;
            if p_expected_version is null then
                raise_application_error(-20901, 'CONFLICT: alternate shift version is required');
            end if;
            update ALTERNATE_SHIFT
               set SHIFT_ID=p_shift_id, "DATE"=cast(trunc(p_work_date) as timestamp)
             where ID=p_entity_id
               and ORA_ROWSCN = p_expected_version;
            if sql%rowcount <> 1 then
                raise_application_error(-20901, 'CONFLICT: alternate shift changed');
            end if;
        exception when no_data_found then
            insert into ALTERNATE_SHIFT (EMPLOYEE_ID,SHIFT_ID,"DATE") values (p_employee_id,p_shift_id,cast(trunc(p_work_date) as timestamp)) returning ID into p_entity_id;
        end;
        select json_object('idempotency_key' value p_idempotency_key returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('TIMESHEET_ALTERNATE_SHIFT','ALTERNATE_SHIFT',p_entity_id,l_audit_details);
        AUDIT_PKG.complete_idempotency('TIMESHEET_ALTERNATE_SHIFT',p_idempotency_key,p_entity_id);
        commit; p_status:='SUCCESS'; p_message:='Alternate shift saved';
    exception when others then
        if sqlcode = -20901 then
            rollback; p_status := 'CONFLICT'; p_message := substr(sqlerrm, 1, 4000);
            AUDIT_PKG.record_rejection('TIMESHEET_ALTERNATE_SHIFT', 'ALTERNATE_SHIFT', p_entity_id, p_message, p_idempotency_key);
        else
            rejected('TIMESHEET_ALTERNATE_SHIFT','ALTERNATE_SHIFT',p_entity_id,sqlerrm,p_idempotency_key,p_status,p_message);
        end if;
    end upsert_alternate_shift;

    procedure record_print_decision(
        p_employee_id number, p_month date, p_decision varchar2,
        p_idempotency_key varchar2, p_status out varchar2, p_message out varchar2
    ) is
        l_decision varchar2(30) := upper(trim(p_decision));
        l_existing_id number;
        l_retry boolean;
        l_audit_details clob;
    begin
        if p_employee_id is null or p_month is null or p_idempotency_key is null or l_decision not in ('PRINTED','DECLINED') then
            raise_application_error(-20194, 'Employee, month, printed/declined decision, and idempotency key are required');
        end if;
        if not AUTH_PKG.can_print_timesheet(p_employee_id, trunc(p_month, 'MM')) then
            raise_application_error(-20195, 'Timesheet printing is not permitted');
        end if;
        AUDIT_PKG.reserve_idempotency('TIMESHEET_PRINT_DECISION',p_idempotency_key,'EMPLOYEE',l_existing_id,l_retry);
        if l_retry then p_status:='IDEMPOTENT'; p_message:='Existing print decision was returned'; return; end if;
        if l_decision='PRINTED' then update EMPLOYEE set LAST_TIMESHEET_PRINT_DATE=systimestamp where ID=p_employee_id; end if;
        select json_object('decision' value l_decision,
                           'month' value to_char(trunc(p_month,'MM'),'YYYY-MM-DD'),
                           'idempotency_key' value p_idempotency_key returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('TIMESHEET_PRINT_DECISION','EMPLOYEE',p_employee_id,l_audit_details);
        AUDIT_PKG.complete_idempotency('TIMESHEET_PRINT_DECISION',p_idempotency_key,p_employee_id);
        commit; p_status:='SUCCESS'; p_message:='Timesheet print decision recorded';
    exception when others then rejected('TIMESHEET_PRINT_DECISION','EMPLOYEE',p_employee_id,sqlerrm,p_idempotency_key,p_status,p_message); end record_print_decision;
end TIMESHEET_API_PKG;
/
