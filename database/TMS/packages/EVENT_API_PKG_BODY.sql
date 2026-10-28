
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."EVENT_API_PKG" as
    procedure require_event_access(p_employee_id number, p_work_date timestamp, p_feature varchar2) is
        l_location_id number;
    begin
        if not AUTH_PKG.can_write(p_feature) then
            raise_application_error(-20160, 'Write access is not granted for ' || p_feature);
        end if;
        select LOCATION_ID into l_location_id from EMPLOYEE
         where ID = p_employee_id and IS_ACTIVE = '1';
        if not AUTH_PKG.can_access_location(l_location_id)
           or not AUTH_PKG.is_month_open(cast(p_work_date as date), l_location_id) then
            raise_application_error(-20161, 'Employee location is out of scope or closed for the work date');
        end if;
    end require_event_access;

    function feature_for(p_event_type varchar2) return varchar2 is
    begin
        return case upper(p_event_type)
          when 'VACATION' then 'WriteVacations'
          when 'MISSION' then 'WriteMissions'
          when 'TRAINING' then 'WriteTrainings'
          when 'PERMISSION' then 'WritePermissions'
          when 'SPECIAL_LEAVE' then 'WriteVacations'
          when 'APPROVED_OVERTIME' then 'WriteVacations'
        end;
    end feature_for;

    procedure require_existing_event(p_event_type varchar2, p_entity_id number) is
        l_employee_id number;
        l_work_date timestamp;
    begin
        if p_event_type = 'VACATION' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from VACATION where ID=p_entity_id and IS_INSERTED_BY_APEX='1' for update;
        elsif p_event_type = 'MISSION' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from MISSION where ID=p_entity_id and IS_INSERTED_BY_APEX='1' for update;
        elsif p_event_type = 'TRAINING' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from TRAINING where ID=p_entity_id and IS_INSERTED_BY_APEX='1' for update;
        elsif p_event_type = 'PERMISSION' then select EMPLOYEE_ID, "DATE" into l_employee_id, l_work_date from PERMISSION where ID=p_entity_id and IS_INSERTED_BY_APEX='1' for update;
        elsif p_event_type = 'SPECIAL_LEAVE' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from SPECIAL_LEAVE where ID=p_entity_id and IS_INSERTED_BY_APEX='1' for update;
        else select EMPLOYEE_ID, "DATE" into l_employee_id, l_work_date from APPROVED_OVERTIME where ID=p_entity_id and IS_INSERTED_BY_APEX='1' for update;
        end if;
        require_event_access(l_employee_id, l_work_date, feature_for(p_event_type));
    end require_existing_event;

    procedure validate_event_rules(p_event_type varchar2, p_entity_id number, p_employee_id number,
                                   p_from_date timestamp, p_to_date timestamp, p_type_id number) is
        l_count number;
        l_code varchar2(100);
    begin
        if p_event_type = 'VACATION' then
            select CODE into l_code from VACATION_TYPE where ID=p_type_id and nvl(IS_ARCHIVE,'0') <> '1';
            select count(*) into l_count from VACATION where EMPLOYEE_ID=p_employee_id and ID<>nvl(p_entity_id,-1) and FROM_DATE<=p_to_date and TO_DATE>=p_from_date;
            if l_count>0 then raise_application_error(-20173,'Vacation overlaps an existing vacation'); end if;
            select count(*) into l_count from MISSION where EMPLOYEE_ID=p_employee_id and FROM_DATE<=p_to_date and TO_DATE>=p_from_date;
            if l_count>0 then raise_application_error(-20174,'Vacation overlaps an existing mission'); end if;
            select count(*) into l_count from TRAINING where EMPLOYEE_ID=p_employee_id and FROM_DATE<=p_to_date and TO_DATE>=p_from_date;
            if l_count>0 then raise_application_error(-20175,'Vacation overlaps an existing training'); end if;
            if upper(l_code)='C' then
                select nvl(sum(trunc(v.TO_DATE) - trunc(v.FROM_DATE) + 1), 0) into l_count
                  from VACATION v join VACATION_TYPE vt on vt.ID=v.TYPE_ID
                 where v.EMPLOYEE_ID=p_employee_id and upper(vt.CODE)='C' and v.ID<>nvl(p_entity_id,-1)
                   and v.FROM_DATE<=p_to_date+interval '2' day and v.TO_DATE>=p_from_date-interval '2' day;
                l_count := l_count + trunc(p_to_date)-trunc(p_from_date)+1;
                if l_count>2 then raise_application_error(-20176,'Casual leave duration or adjacency exceeds two days'); end if;
            end if;
        elsif p_event_type in ('MISSION','TRAINING') then
            select count(*) into l_count from VACATION where EMPLOYEE_ID=p_employee_id and FROM_DATE<=p_to_date and TO_DATE>=p_from_date;
            if l_count>0 then raise_application_error(-20177,'Mission or training overlaps vacation'); end if;
            select count(*) into l_count from MISSION where EMPLOYEE_ID=p_employee_id and ID<>case when p_event_type='MISSION' then nvl(p_entity_id,-1) else -1 end and FROM_DATE<=p_to_date and TO_DATE>=p_from_date;
            if l_count>0 then raise_application_error(-20178,'Mission or training overlaps mission'); end if;
            select count(*) into l_count from TRAINING where EMPLOYEE_ID=p_employee_id and ID<>case when p_event_type='TRAINING' then nvl(p_entity_id,-1) else -1 end and FROM_DATE<=p_to_date and TO_DATE>=p_from_date;
            if l_count>0 then raise_application_error(-20179,'Mission or training overlaps training'); end if;
        elsif p_event_type='PERMISSION' then
            select ID into l_count from PERMISSION_TYPE where ID=p_type_id;
            select count(*) into l_count from PERMISSION where EMPLOYEE_ID=p_employee_id and ID<>nvl(p_entity_id,-1) and trunc("DATE")=trunc(p_from_date) and FROM_TIME<p_to_date and TO_TIME>p_from_date;
            if l_count>0 then raise_application_error(-20180,'Permission overlaps an existing permission'); end if;
        elsif p_event_type='SPECIAL_LEAVE' then
            select ID into l_count from SPECIAL_LEAVE_TYPE where ID=p_type_id;
        end if;
    end validate_event_rules;

    procedure rejected(p_operation varchar2, p_entity_type varchar2, p_entity_id number,
                       p_error varchar2, p_key varchar2, p_status out varchar2,
                       p_message out varchar2) is
    begin
        rollback;
        p_status := 'REJECTED'; p_message := substr(p_error, 1, 4000);
        AUDIT_PKG.record_rejection(p_operation, p_entity_type, p_entity_id, p_message, p_key);
    end rejected;

    procedure get_audit_events(
        p_from timestamp, p_to timestamp, p_event_code varchar2, p_rows out sys_refcursor
    ) is
    begin
        open p_rows for
            select ID, EVENT_TIME, APP_USER_ID, EVENT_CODE, ENTITY_TYPE, ENTITY_ID,
                   CORRELATION_ID, SUCCESS_FLAG,
                   json_object('details_redacted' value case when DETAILS_JSON is null then 'N' else 'Y' end returning clob) as DETAILS_JSON
              from AUDIT_EVENT
             where (p_from is null or EVENT_TIME >= p_from)
               and (p_to is null or EVENT_TIME < p_to)
               and (p_event_code is null or EVENT_CODE = p_event_code)
             order by EVENT_TIME desc, ID desc;
end get_audit_events;

    procedure get_vacations(p_filters_json clob, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select v.ID, v.EMPLOYEE_ID, v.FROM_DATE, v.TO_DATE, v.TYPE_ID
              from VACATION v join EMPLOYEE e on e.ID = v.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
             order by v.FROM_DATE desc;
    end get_vacations;

    procedure get_missions(p_filters_json clob, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select m.ID, m.EMPLOYEE_ID, m.FROM_DATE, m.TO_DATE, m.DESCRIPTION
              from MISSION m join EMPLOYEE e on e.ID = m.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
             order by m.FROM_DATE desc;
    end get_missions;

    procedure get_trainings(p_filters_json clob, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select t.ID, t.EMPLOYEE_ID, t.FROM_DATE, t.TO_DATE, t.DESCRIPTION
              from TRAINING t join EMPLOYEE e on e.ID = t.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
             order by t.FROM_DATE desc;
    end get_trainings;

    procedure get_permissions(p_filters_json clob, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select p.ID, p.EMPLOYEE_ID, p."DATE", p.FROM_TIME, p.TO_TIME, p.TYPE_ID, p.DESCRIPTION
              from PERMISSION p join EMPLOYEE e on e.ID = p.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
             order by p."DATE" desc;
    end get_permissions;

    procedure get_approved_overtime(p_filters_json clob, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select a.ID, a."DATE", a.FROM_TIME, a.TO_TIME, a.EMPLOYEE_ID, a.DESCRIPTION
              from APPROVED_OVERTIME a join EMPLOYEE e on e.ID = a.EMPLOYEE_ID
             where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
             order by a."DATE" desc;
    end get_approved_overtime;

    procedure upsert_event(
        p_event_type varchar2, p_entity_id number, p_employee_id number,
        p_from_date timestamp, p_to_date timestamp, p_type_id number,
        p_description varchar2, p_expected_version number, p_idempotency_key varchar2,
        p_result_id out number, p_status out varchar2, p_message out varchar2
    ) is
        l_type varchar2(30) := upper(trim(p_event_type));
        l_existing_id number;
        l_is_retry boolean;
        l_from_time timestamp;
        l_to_time timestamp;
        l_audit_details clob;
    begin
        if l_type not in ('VACATION', 'MISSION', 'TRAINING', 'PERMISSION', 'SPECIAL_LEAVE', 'APPROVED_OVERTIME')
           or p_employee_id is null or p_from_date is null or p_to_date is null
           or p_from_date >= p_to_date or p_idempotency_key is null then
            raise_application_error(-20162, 'Valid event type, employee, date range, and idempotency key are required');
        end if;
        if p_entity_id is not null then require_existing_event(l_type, p_entity_id); end if;
        require_event_access(p_employee_id, p_from_date, feature_for(l_type));
        require_event_access(p_employee_id, p_to_date, feature_for(l_type));
        validate_event_rules(l_type, p_entity_id, p_employee_id, p_from_date, p_to_date, p_type_id);
        AUDIT_PKG.reserve_idempotency('EVENT_'||l_type||'_UPSERT', p_idempotency_key, l_type, l_existing_id, l_is_retry);
        if l_is_retry then
            p_result_id := l_existing_id; p_status := 'IDEMPOTENT';
            p_message := 'Existing event was returned'; return;
        end if;
        if l_type = 'VACATION' then
            if p_type_id is null then raise_application_error(-20163, 'Vacation type is required'); end if;
            if p_entity_id is null then
                insert into VACATION (EMPLOYEE_ID, FROM_DATE, TO_DATE, TYPE_ID, IS_INSERTED_BY_APEX, CREATION_DATE)
                values (p_employee_id, p_from_date, p_to_date, p_type_id, '1', systimestamp)
                returning ID into p_result_id;
            else
                update VACATION set EMPLOYEE_ID = p_employee_id, FROM_DATE = p_from_date,
                    TO_DATE = p_to_date, TYPE_ID = p_type_id, LAST_UPDATE_DATE = systimestamp
                 where ID = p_entity_id and IS_INSERTED_BY_APEX = '1' and ORA_ROWSCN=p_expected_version;
                if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: vacation changed or is not package-owned'); end if;
                p_result_id := p_entity_id;
            end if;
        elsif l_type in ('MISSION', 'TRAINING') then
            if p_entity_id is null then
                if l_type = 'MISSION' then
                    insert into MISSION (EMPLOYEE_ID, FROM_DATE, TO_DATE, DESCRIPTION, IS_INSERTED_BY_APEX, CREATION_DATE)
                    values (p_employee_id, p_from_date, p_to_date, p_description, '1', systimestamp)
                    returning ID into p_result_id;
                else
                    insert into TRAINING (EMPLOYEE_ID, FROM_DATE, TO_DATE, DESCRIPTION, IS_INSERTED_BY_APEX, CREATION_DATE)
                    values (p_employee_id, p_from_date, p_to_date, p_description, '1', systimestamp)
                    returning ID into p_result_id;
                end if;
            else
                if l_type = 'MISSION' then
                    update MISSION set EMPLOYEE_ID = p_employee_id, FROM_DATE = p_from_date, TO_DATE = p_to_date,
                    DESCRIPTION = p_description, LAST_UPDATE_DATE = systimestamp
                     where ID = p_entity_id and IS_INSERTED_BY_APEX = '1' and ORA_ROWSCN=p_expected_version;
                else
                    update TRAINING set EMPLOYEE_ID = p_employee_id, FROM_DATE = p_from_date, TO_DATE = p_to_date,
                    DESCRIPTION = p_description, LAST_UPDATE_DATE = systimestamp
                     where ID = p_entity_id and IS_INSERTED_BY_APEX = '1' and ORA_ROWSCN=p_expected_version;
                end if;
                if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: event changed or is not package-owned'); end if;
                p_result_id := p_entity_id;
            end if;
        elsif l_type = 'PERMISSION' then
            if p_type_id is null or trunc(p_from_date) <> trunc(p_to_date) then
                raise_application_error(-20166, 'Permission type and same-day time range are required');
            end if;
            if p_entity_id is null then
                insert into PERMISSION (EMPLOYEE_ID, "DATE", FROM_TIME, TO_TIME, TYPE_ID, DESCRIPTION,
                                        IS_INSERTED_BY_APEX, CREATION_DATE)
                values (p_employee_id, trunc(p_from_date), p_from_date, p_to_date, p_type_id, p_description, '1', systimestamp)
                returning ID into p_result_id;
            else
                update PERMISSION set EMPLOYEE_ID = p_employee_id, "DATE" = trunc(p_from_date),
                    FROM_TIME = p_from_date, TO_TIME = p_to_date, TYPE_ID = p_type_id,
                    DESCRIPTION = p_description, LAST_UPDATE_DATE = systimestamp
                where ID = p_entity_id and IS_INSERTED_BY_APEX = '1' and ORA_ROWSCN=p_expected_version;
                if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: permission changed or is not package-owned'); end if;
                p_result_id := p_entity_id;
            end if;
        elsif l_type = 'SPECIAL_LEAVE' then
            if p_type_id is null then raise_application_error(-20168, 'Special-leave type is required'); end if;
            if p_entity_id is null then
                insert into SPECIAL_LEAVE (EMPLOYEE_ID, FROM_DATE, TO_DATE, TYPE_ID, IS_INSERTED_BY_APEX)
                values (p_employee_id, p_from_date, p_to_date, p_type_id, '1') returning ID into p_result_id;
            else
                update SPECIAL_LEAVE set EMPLOYEE_ID = p_employee_id, FROM_DATE = p_from_date,
                    TO_DATE = p_to_date, TYPE_ID = p_type_id where ID = p_entity_id and IS_INSERTED_BY_APEX = '1' and ORA_ROWSCN=p_expected_version;
                if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: special leave changed or is not package-owned'); end if;
                p_result_id := p_entity_id;
            end if;
        else
            if p_entity_id is null then
                select count(*) into l_existing_id from APPROVED_OVERTIME
                 where EMPLOYEE_ID = p_employee_id and trunc("DATE") = trunc(p_from_date);
                if l_existing_id > 0 then raise_application_error(-20170, 'Another approved overtime exists on the work date'); end if;
                insert into APPROVED_OVERTIME (EMPLOYEE_ID, "DATE", FROM_TIME, TO_TIME, DESCRIPTION,
                                               IS_INSERTED_BY_APEX, CREATION_DATE)
                values (p_employee_id, trunc(p_from_date), p_from_date, p_to_date, p_description, '1', systimestamp)
                returning ID into p_result_id;
            else
                update APPROVED_OVERTIME set EMPLOYEE_ID = p_employee_id, "DATE" = trunc(p_from_date),
                    FROM_TIME = p_from_date, TO_TIME = p_to_date, DESCRIPTION = p_description,
                    LAST_UPDATE_DATE = systimestamp where ID = p_entity_id and IS_INSERTED_BY_APEX = '1' and ORA_ROWSCN=p_expected_version;
                if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: approved overtime changed or is not package-owned'); end if;
                p_result_id := p_entity_id;
            end if;
        end if;
        select json_object('idempotency_key' value p_idempotency_key returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('EVENT_' || l_type || '_UPSERT', l_type, p_result_id, l_audit_details);
        AUDIT_PKG.complete_idempotency('EVENT_'||l_type||'_UPSERT', p_idempotency_key, p_result_id);
        commit;
        p_status := 'SUCCESS'; p_message := 'Event saved';
    exception when others then
        if sqlcode=-20901 then rollback; p_status := 'CONFLICT'; p_message := substr(sqlerrm,1,4000); return; end if;
        rejected('EVENT_' || nvl(l_type, 'UNKNOWN') || '_UPSERT', nvl(l_type, 'EVENT'), p_entity_id,
                 sqlerrm, p_idempotency_key, p_status, p_message);
    end upsert_event;

    procedure delete_event(
        p_event_type varchar2, p_entity_id number, p_status out varchar2, p_message out varchar2
    ) is
        l_type varchar2(30) := upper(trim(p_event_type));
        l_employee_id number;
        l_work_date timestamp;
    begin
        if l_type = 'VACATION' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from VACATION where ID = p_entity_id and IS_INSERTED_BY_APEX = '1';
        elsif l_type = 'MISSION' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from MISSION where ID = p_entity_id and IS_INSERTED_BY_APEX = '1';
        elsif l_type = 'TRAINING' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from TRAINING where ID = p_entity_id and IS_INSERTED_BY_APEX = '1';
        elsif l_type = 'PERMISSION' then select EMPLOYEE_ID, "DATE" into l_employee_id, l_work_date from PERMISSION where ID = p_entity_id and IS_INSERTED_BY_APEX = '1';
        elsif l_type = 'SPECIAL_LEAVE' then select EMPLOYEE_ID, FROM_DATE into l_employee_id, l_work_date from SPECIAL_LEAVE where ID = p_entity_id and IS_INSERTED_BY_APEX = '1';
        elsif l_type = 'APPROVED_OVERTIME' then select EMPLOYEE_ID, "DATE" into l_employee_id, l_work_date from APPROVED_OVERTIME where ID = p_entity_id and IS_INSERTED_BY_APEX = '1';
        else raise_application_error(-20172, 'Unsupported event type'); end if;
        require_event_access(l_employee_id, l_work_date, feature_for(l_type));
        if l_type = 'VACATION' then delete from VACATION where ID = p_entity_id;
        elsif l_type = 'MISSION' then delete from MISSION where ID = p_entity_id;
        elsif l_type = 'TRAINING' then delete from TRAINING where ID = p_entity_id;
        elsif l_type = 'PERMISSION' then delete from PERMISSION where ID = p_entity_id;
        elsif l_type = 'SPECIAL_LEAVE' then delete from SPECIAL_LEAVE where ID = p_entity_id and IS_INSERTED_BY_APEX = '1';
        else delete from APPROVED_OVERTIME where ID = p_entity_id; end if;
        AUDIT_PKG.record_event('EVENT_' || l_type || '_DELETE', l_type, p_entity_id, null);
        commit;
        p_status := 'SUCCESS'; p_message := 'Event deleted';
    exception when others then
        rejected('EVENT_' || nvl(l_type, 'UNKNOWN') || '_DELETE', nvl(l_type, 'EVENT'), p_entity_id,
                 sqlerrm, null, p_status, p_message);
    end delete_event;

    procedure upsert_vacation(
        p_vacation_id number, p_employee_id number, p_from_date timestamp,
        p_to_date timestamp, p_type_id number, p_idempotency_key varchar2,
        p_entity_id out number, p_status out varchar2, p_message out varchar2
    ) is
    begin
        upsert_event('VACATION', p_vacation_id, p_employee_id, p_from_date, p_to_date,
            p_type_id, null, null, p_idempotency_key, p_entity_id, p_status, p_message);
    end upsert_vacation;
end EVENT_API_PKG;
/
