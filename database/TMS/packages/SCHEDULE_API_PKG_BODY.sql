
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."SCHEDULE_API_PKG" as
    procedure require_schedule_admin is
    begin
        if not (AUTH_PKG.has_role('1') or AUTH_PKG.has_role('2')) then
            raise_application_error(-20180, 'Schedule administration requires role 1 or 2');
        end if;
    end require_schedule_admin;

    procedure require_open_employee(p_employee_id number, p_work_date timestamp) is
        l_location_id number;
    begin
        select LOCATION_ID into l_location_id from EMPLOYEE where ID=p_employee_id and IS_ACTIVE='1';
        if not AUTH_PKG.can_access_location(l_location_id)
           or not AUTH_PKG.is_month_open(cast(p_work_date as date), l_location_id) then
            raise_application_error(-20190, 'Employee location is out of scope or closed for the schedule date');
        end if;
    end require_open_employee;

    procedure require_existing_schedule_employee(p_schedule_type varchar2, p_entity_id number) is
        l_employee_id number;
        l_work_date timestamp;
    begin
        if p_schedule_type='ROTATION_HISTORY' then select EMPLOYEE_ID,STARTED into l_employee_id,l_work_date from ROTATION_HISTORY where ID=p_entity_id for update;
        else select EMPLOYEE_ID,"DATE" into l_employee_id,l_work_date from ALTERNATE_SHIFT where ID=p_entity_id for update; end if;
        require_open_employee(l_employee_id,l_work_date);
    end require_existing_schedule_employee;

    procedure require_existing_month_cut(p_entity_id number) is
        l_location_id number;
    begin
        select LOCATION_ID into l_location_id from MONTH_CUT_DATE where ID=p_entity_id for update;
        if not AUTH_PKG.can_access_location(l_location_id) then
            raise_application_error(-20191, 'Existing month cut is out of scope');
        end if;
    end require_existing_month_cut;

    procedure rejected(p_operation varchar2, p_entity_type varchar2, p_entity_id number,
                       p_error varchar2, p_key varchar2, p_status out varchar2,
                       p_message out varchar2) is
    begin
        rollback; p_status := 'REJECTED'; p_message := substr(p_error, 1, 4000);
        AUDIT_PKG.record_rejection(p_operation, p_entity_type, p_entity_id, p_message, p_key);
    end rejected;

    procedure get_shifts(p_rows out sys_refcursor) is
    begin
        open p_rows for select ID, NAME, FROM_DATE, DURATION, IS_OFF from SHIFT order by NAME;
    end get_shifts;

    procedure get_rotation_plans(p_rows out sys_refcursor) is
    begin
        open p_rows for
            select rp.ID, rp.NAME, rp.DAYS, rp.START_DATE, rp.IS_VISIBLE, rp.WORK_TYPE,
                   rd.DAY, rd.SHIFT_ID
              from ROTATION_PLAN rp
              left join ROTATION_DAY rd on rd.ROTATION_ID = rp.ID
             order by rp.NAME, rd.DAY;
    end get_rotation_plans;

    procedure get_rotation_history(p_employee_id number, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select ID, EMPLOYEE_ID, ROTATION_ID, STARTED, CREATION_DATE
              from ROTATION_HISTORY
             where (p_employee_id is null or EMPLOYEE_ID = p_employee_id)
               and exists (select 1 from EMPLOYEE e where e.ID = EMPLOYEE_ID
                             and AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1)
             order by STARTED desc, ID desc;
    end get_rotation_history;

    procedure get_alternate_shifts(p_employee_id number, p_from date, p_to date, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select ID, EMPLOYEE_ID, SHIFT_ID, "DATE"
              from ALTERNATE_SHIFT
             where (p_employee_id is null or EMPLOYEE_ID = p_employee_id)
               and exists (select 1 from EMPLOYEE e where e.ID = EMPLOYEE_ID
                             and AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1)
               and (p_from is null or "DATE" >= p_from)
               and (p_to is null or "DATE" < p_to)
             order by "DATE", ID;
    end get_alternate_shifts;

    procedure get_holidays(p_from timestamp, p_to timestamp, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select ID, NAME, FROM_DATE, TO_DATE, TARGET_NATIONALITY, TARGET_RELIGION, WORK_TYPE
              from OFFICIAL_HOLIDAY
             where (p_from is null or TO_DATE >= p_from)
               and (p_to is null or FROM_DATE < p_to)
             order by FROM_DATE, ID;
    end get_holidays;

    procedure get_month_cut_dates(p_location_id number, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select ID, MONTH, YEAR, CUT_DATE, LOCATION_ID
              from MONTH_CUT_DATE
             where (p_location_id is null or LOCATION_ID = p_location_id)
               and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1
             order by YEAR desc, MONTH desc, LOCATION_ID;
    end get_month_cut_dates;

    procedure upsert_schedule(
        p_schedule_type varchar2, p_entity_id number, p_employee_id number,
        p_location_id number, p_name varchar2, p_from_date timestamp,
        p_to_date timestamp, p_value_1 varchar2, p_value_2 number,
        p_text_1 varchar2, p_text_2 varchar2, p_expected_version number, p_idempotency_key varchar2,
        p_result_id out number, p_status out varchar2, p_message out varchar2
    ) is
        l_type varchar2(30) := upper(trim(p_schedule_type));
        l_existing_id number;
        l_retry boolean;
        l_audit_details clob;
    begin
        require_schedule_admin;
        if l_type not in ('SHIFT','ROTATION_PLAN','ROTATION_DAY','ROTATION_HISTORY','ALTERNATE_SHIFT','HOLIDAY','MONTH_CUT_DATE')
           or p_idempotency_key is null then
            raise_application_error(-20181, 'Supported schedule type and idempotency key are required');
        end if;
        if l_type = 'MONTH_CUT_DATE' and (p_location_id is null or not AUTH_PKG.can_access_location(p_location_id)) then
            raise_application_error(-20182, 'A permitted location is required for month cut dates');
        end if;
        if l_type = 'MONTH_CUT_DATE' and p_entity_id is not null then
            require_existing_month_cut(p_entity_id);
        end if;
        if l_type in ('ROTATION_HISTORY','ALTERNATE_SHIFT') then
            if p_entity_id is not null then require_existing_schedule_employee(l_type,p_entity_id); end if;
            require_open_employee(p_employee_id,p_from_date);
        end if;
        AUDIT_PKG.reserve_idempotency('SCHEDULE_'||l_type||'_UPSERT',p_idempotency_key,l_type,l_existing_id,l_retry);
        if l_retry then p_result_id:=l_existing_id; p_status:='IDEMPOTENT'; p_message:='Existing schedule row was returned'; return; end if;
        if l_type = 'SHIFT' then
            if trim(p_name) is null or p_from_date is null or p_value_1 is null or not regexp_like(p_value_1, '^[0-9]+$') or to_number(p_value_1) <= 0 then raise_application_error(-20192,'Shift name, start time, and duration are required'); end if;
            select count(*) into l_existing_id from SHIFT where upper(NAME)=upper(trim(p_name)) and ID<>nvl(p_entity_id,-1);
            if l_existing_id>0 then raise_application_error(-20193,'A shift with this name already exists'); end if;
            if p_entity_id is null then insert into SHIFT (NAME, FROM_DATE, DURATION, IS_OFF) values (trim(p_name), p_from_date, to_number(p_value_1), nvl(p_text_1, '0')) returning ID into p_result_id;
            else update SHIFT set NAME=trim(p_name), FROM_DATE=p_from_date, DURATION=to_number(p_value_1), IS_OFF=nvl(p_text_1,'0') where ID=p_entity_id and ORA_ROWSCN=p_expected_version; if sql%rowcount<>1 then raise_application_error(-20901,'CONFLICT: shift changed by another user'); end if; p_result_id:=p_entity_id; end if;
        elsif l_type = 'ROTATION_PLAN' then
            if trim(p_name) is null or p_from_date is null or trim(p_text_2) is null then raise_application_error(-20194,'Rotation plan name, start date, and work type are required'); end if;
            if p_value_1 is null or not regexp_like(p_value_1, '^[0-9]+$') or to_number(p_value_1) not between 1 and 30 then raise_application_error(-20195,'Rotation plan days must be between 1 and 30'); end if;
            select count(*) into l_existing_id from ROTATION_PLAN where upper(NAME)=upper(trim(p_name)) and ID<>nvl(p_entity_id,-1);
            if l_existing_id>0 then raise_application_error(-20196,'A rotation plan with this name already exists'); end if;
            if p_entity_id is null then insert into ROTATION_PLAN (NAME,DAYS,START_DATE,IS_VISIBLE,WORK_TYPE) values (trim(p_name),to_number(p_value_1),p_from_date,nvl(p_text_1,'1'),p_text_2) returning ID into p_result_id;
            else update ROTATION_PLAN set NAME=trim(p_name),DAYS=to_number(p_value_1),START_DATE=p_from_date,IS_VISIBLE=nvl(p_text_1,'1'),WORK_TYPE=p_text_2 where ID=p_entity_id and ORA_ROWSCN=p_expected_version; if sql%rowcount<>1 then raise_application_error(-20901,'CONFLICT: rotation plan changed by another user'); end if; p_result_id:=p_entity_id; end if;
        elsif l_type = 'ROTATION_DAY' then
            if p_value_1 is null or not regexp_like(p_value_1, '^[0-9]+$') or p_value_2 is null or p_text_1 is null or not regexp_like(p_text_1, '^[0-9]+$') or to_number(p_text_1) not between 1 and 30 then raise_application_error(-20197,'Rotation, shift, and day 1-30 are required'); end if;
            select count(*) into l_existing_id from ROTATION_DAY where ROTATION_ID=to_number(p_value_1) and DAY=to_number(p_text_1) and ID<>nvl(p_entity_id,-1);
            if l_existing_id>0 then raise_application_error(-20198,'A rotation day already exists for this rotation'); end if;
            if p_entity_id is null then insert into ROTATION_DAY (ROTATION_ID,SHIFT_ID,DAY) values (to_number(p_value_1),p_value_2,to_number(p_text_1)) returning ID into p_result_id;
            else update ROTATION_DAY set ROTATION_ID=to_number(p_value_1),SHIFT_ID=p_value_2,DAY=to_number(p_text_1) where ID=p_entity_id and ORA_ROWSCN=p_expected_version; if sql%rowcount<>1 then raise_application_error(-20901,'CONFLICT: rotation day changed by another user'); end if; p_result_id:=p_entity_id; end if;
        elsif l_type = 'ROTATION_HISTORY' then
            if p_employee_id is null then raise_application_error(-20183,'Employee is required for rotation history'); end if;
            if not regexp_like(p_value_1, '^[0-9]+$') then raise_application_error(-20183,'Rotation is required for rotation history'); end if;
            if p_entity_id is null then insert into ROTATION_HISTORY (EMPLOYEE_ID,ROTATION_ID,STARTED,CREATION_DATE) values (p_employee_id,to_number(p_value_1),p_from_date,systimestamp) returning ID into p_result_id;
            else update ROTATION_HISTORY set EMPLOYEE_ID=p_employee_id,ROTATION_ID=to_number(p_value_1),STARTED=p_from_date where ID=p_entity_id and ORA_ROWSCN=p_expected_version; if sql%rowcount<>1 then raise_application_error(-20901,'CONFLICT: rotation history changed'); end if; p_result_id:=p_entity_id; end if;
        elsif l_type = 'ALTERNATE_SHIFT' then
            if p_employee_id is null then raise_application_error(-20184,'Employee is required for alternate shift'); end if;
            if not regexp_like(p_value_1, '^[0-9]+$') then raise_application_error(-20184,'Shift is required for alternate shift'); end if;
            if p_entity_id is null then insert into ALTERNATE_SHIFT (EMPLOYEE_ID,SHIFT_ID,"DATE") values (p_employee_id,to_number(p_value_1),p_from_date) returning ID into p_result_id;
            else update ALTERNATE_SHIFT set EMPLOYEE_ID=p_employee_id,SHIFT_ID=to_number(p_value_1),"DATE"=p_from_date where ID=p_entity_id and ORA_ROWSCN=p_expected_version; if sql%rowcount<>1 then raise_application_error(-20901,'CONFLICT: alternate shift changed'); end if; p_result_id:=p_entity_id; end if;
        elsif l_type = 'HOLIDAY' then
            if trim(p_name) is null or p_from_date is null or p_to_date is null or trim(p_text_1) is null or trim(p_text_2) is null or p_value_1 is null then raise_application_error(-20199,'Holiday name, dates, nationality, religion, and work type are required'); end if;
            if p_from_date > p_to_date then raise_application_error(-20200,'Holiday dates must be ordered'); end if;
            if p_entity_id is null and trunc(p_from_date,'MM')<>trunc(p_to_date,'MM') then raise_application_error(-20201,'Holiday create dates must be in the same month'); end if;
            if p_entity_id is null then insert into OFFICIAL_HOLIDAY (NAME,FROM_DATE,TO_DATE,TARGET_NATIONALITY,TARGET_RELIGION,WORK_TYPE) values (trim(p_name),p_from_date,p_to_date,p_text_1,p_text_2,p_value_1) returning ID into p_result_id;
            else update OFFICIAL_HOLIDAY set NAME=trim(p_name),FROM_DATE=p_from_date,TO_DATE=p_to_date,TARGET_NATIONALITY=p_text_1,TARGET_RELIGION=p_text_2,WORK_TYPE=p_value_1 where ID=p_entity_id and ORA_ROWSCN=p_expected_version; if sql%rowcount<>1 then raise_application_error(-20901,'CONFLICT: holiday changed by another user'); end if; p_result_id:=p_entity_id; end if;
        else
            if p_from_date is null or p_to_date is null or extract(month from p_from_date) not between 1 and 12 then raise_application_error(-20185,'Month and cut date are required'); end if;
            if p_entity_id is null then
                select count(*) into l_existing_id from MONTH_CUT_DATE where MONTH=extract(month from p_from_date) and YEAR=extract(year from p_from_date) and LOCATION_ID=p_location_id;
                if l_existing_id>0 then raise_application_error(-20186,'A month cut already exists for this location and month'); end if;
                insert into MONTH_CUT_DATE (MONTH,YEAR,CUT_DATE,LOCATION_ID,CREATION_DATE) values (extract(month from p_from_date),extract(year from p_from_date),p_to_date,p_location_id,systimestamp) returning ID into p_result_id;
            else update MONTH_CUT_DATE set MONTH=extract(month from p_from_date),YEAR=extract(year from p_from_date),CUT_DATE=p_to_date,LOCATION_ID=p_location_id,LAST_UPDATE_DATE=systimestamp where ID=p_entity_id and ORA_ROWSCN=p_expected_version; if sql%rowcount<>1 then raise_application_error(-20901,'CONFLICT: month cut changed'); end if; p_result_id:=p_entity_id; end if;
        end if;
        if p_entity_id is not null and sql%rowcount <> 1 then raise_application_error(-20187,'Schedule row was not found'); end if;
        select json_object('idempotency_key' value p_idempotency_key returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('SCHEDULE_' || l_type || '_UPSERT', l_type, p_result_id, l_audit_details);
        AUDIT_PKG.complete_idempotency('SCHEDULE_'||l_type||'_UPSERT',p_idempotency_key,p_result_id);
        commit; p_status:='SUCCESS'; p_message:='Schedule saved';
    exception when others then
        if sqlcode=-20901 then rollback; p_status := 'CONFLICT'; p_message := substr(sqlerrm,1,4000); return; end if;
        rejected('SCHEDULE_' || nvl(l_type,'UNKNOWN') || '_UPSERT', nvl(l_type,'SCHEDULE'), p_entity_id, sqlerrm, p_idempotency_key, p_status, p_message);
    end upsert_schedule;

    procedure delete_schedule(p_schedule_type varchar2, p_entity_id number, p_status out varchar2, p_message out varchar2) is
        l_type varchar2(30) := upper(trim(p_schedule_type));
    begin
        require_schedule_admin;
        if l_type='SHIFT' then delete from SHIFT where ID=p_entity_id;
        elsif l_type='ROTATION_PLAN' then delete from ROTATION_PLAN where ID=p_entity_id;
        elsif l_type='ROTATION_DAY' then delete from ROTATION_DAY where ID=p_entity_id;
        elsif l_type='ROTATION_HISTORY' then require_existing_schedule_employee(l_type,p_entity_id); delete from ROTATION_HISTORY where ID=p_entity_id;
        elsif l_type='ALTERNATE_SHIFT' then require_existing_schedule_employee(l_type,p_entity_id); delete from ALTERNATE_SHIFT where ID=p_entity_id;
        elsif l_type='HOLIDAY' then delete from OFFICIAL_HOLIDAY where ID=p_entity_id;
        elsif l_type='MONTH_CUT_DATE' then require_existing_month_cut(p_entity_id); delete from MONTH_CUT_DATE where ID=p_entity_id and AUTH_PKG.can_access_location_sql(LOCATION_ID)=1;
        else raise_application_error(-20188,'Unsupported schedule type'); end if;
        if sql%rowcount<>1 then raise_application_error(-20189,'Schedule row was not found or is out of scope'); end if;
        AUDIT_PKG.record_event('SCHEDULE_'||l_type||'_DELETE',l_type,p_entity_id,null); commit; p_status:='SUCCESS'; p_message:='Schedule deleted';
    exception when others then rejected('SCHEDULE_'||nvl(l_type,'UNKNOWN')||'_DELETE',nvl(l_type,'SCHEDULE'),p_entity_id,sqlerrm,null,p_status,p_message); end delete_schedule;
end SCHEDULE_API_PKG;
/
