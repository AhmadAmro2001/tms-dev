
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."TRANSACTION_API_PKG" as
    procedure require_operator is
    begin
        if not (AUTH_PKG.has_role('1') or AUTH_PKG.has_role('2')) then
            raise_application_error(-20150, 'Transaction writes require role 1 or 2');
        end if;
    end require_operator;

    procedure require_open_employee(p_employee_id number, p_work_date timestamp) is
        l_location_id number;
    begin
        select LOCATION_ID into l_location_id from EMPLOYEE
         where ID = p_employee_id and IS_ACTIVE = '1';
        if not AUTH_PKG.can_access_location(l_location_id)
           or not AUTH_PKG.is_month_open(cast(p_work_date as date), l_location_id) then
            raise_application_error(-20151, 'Employee location is out of scope or closed for the work date');
        end if;
    end require_open_employee;

    procedure rejected(p_operation varchar2, p_entity_type varchar2, p_entity_id number,
                       p_error varchar2, p_key varchar2, p_status out varchar2,
                       p_message out varchar2) is
    begin
        rollback;
        p_status := 'REJECTED'; p_message := substr(p_error, 1, 4000);
        AUDIT_PKG.record_rejection(p_operation, p_entity_type, p_entity_id, p_message, p_key);
    end rejected;

    procedure get_transactions(
        p_employee_number varchar2, p_from timestamp, p_to timestamp,
        p_location_id number, p_rows out sys_refcursor
    ) is
    begin
        open p_rows for
        select t.*
        from V_TRANSACTION t
        join V_EMPLOYEE e on e.ID = t.EMPLOYEE_ID
        where (p_employee_number is null or to_char(e.EMPLOYEE_NUMBER) = p_employee_number)
          and (p_from is null or t."DATE" >= p_from)
          and (p_to is null or t."DATE" < p_to)
          and AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
          and (p_location_id is null or e.LOCATION_ID = p_location_id)
        order by t."DATE" desc;
    end get_transactions;

    procedure get_unmatched_punches(p_from timestamp, p_to timestamp, p_rows out sys_refcursor) is
    begin
        open p_rows for select * from V_UNMATCHED_PUNCH
        where (p_from is null or SOURCE_TIMESTAMP >= p_from)
          and (p_to is null or SOURCE_TIMESTAMP < p_to)
        order by SOURCE_TIMESTAMP desc;
    end get_unmatched_punches;

    procedure stage_transactions(p_batch_id number, p_payload clob, p_result out clob) is
    begin
        if p_batch_id is null or p_payload is null then
            raise_application_error(-20002, 'Batch ID and transaction payload are required');
        end if;
        select json_object(
            'success' value false,
            'code' value 'SOURCE_ROUTE_REQUIRED',
            'message' value 'Transaction staging requires the approved source payload contract'
            returning clob
        ) into p_result from dual;
        AUDIT_PKG.record_event('TRANSACTION_STAGE_REJECTED', 'TRANSACTION_STAGE', p_batch_id, p_result);
    end stage_transactions;

    procedure upsert_manual_transaction(
        p_transaction_id number, p_employee_id number, p_event_type char,
        p_event_time timestamp, p_device_id number, p_device_name varchar2,
        p_expected_version number, p_idempotency_key varchar2, p_entity_id out number,
        p_status out varchar2, p_message out varchar2
    ) is
        l_existing_id number;
        l_device_name DEVICE.NAME%type;
        l_retry boolean;
        l_existing_work_date timestamp;
        l_audit_details clob;
    begin
        require_operator;
        if p_employee_id is null or p_event_type not in ('0', '1') or p_event_time is null
           or p_idempotency_key is null then
            raise_application_error(-20152, 'Employee, in/out type, timestamp, and idempotency key are required');
        end if;
        require_open_employee(p_employee_id, p_event_time);
        if p_device_id is not null then
            select NAME into l_device_name from DEVICE where ID = p_device_id;
        else
            l_device_name := p_device_name;
        end if;
        if p_transaction_id is not null then
            select EMPLOYEE_ID, "DATE" into l_existing_id, l_existing_work_date from "TRANSACTION" where ID=p_transaction_id for update;
            require_open_employee(l_existing_id, l_existing_work_date);
        end if;
        AUDIT_PKG.reserve_idempotency('TRANSACTION_MANUAL_UPSERT', p_idempotency_key, 'TRANSACTION', l_existing_id, l_retry);
        if l_retry then
            p_entity_id := l_existing_id; p_status := 'IDEMPOTENT';
            p_message := 'Existing manual transaction was returned'; return;
        end if;
        if p_transaction_id is null then
            select max(ID) into l_existing_id from "TRANSACTION"
             where EMPLOYEE_ID = p_employee_id and TYPE = p_event_type and "DATE" = p_event_time
               and nvl(DEVICE_ID, -1) = nvl(p_device_id, -1);
            if l_existing_id is not null then
                AUDIT_PKG.complete_idempotency('TRANSACTION_MANUAL_UPSERT', p_idempotency_key, l_existing_id);
                commit;
                p_entity_id := l_existing_id; p_status := 'IDEMPOTENT';
                p_message := 'Matching manual transaction already exists'; return;
            end if;
            insert into "TRANSACTION" (EMPLOYEE_ID, TYPE, "DATE", DEVICE_ID, DEVICE_NAME, CREATION_DATE)
            values (p_employee_id, p_event_type, p_event_time, p_device_id, l_device_name, systimestamp)
            returning ID into p_entity_id;
        else
            update "TRANSACTION"
               set TYPE = p_event_type, "DATE" = p_event_time, DEVICE_ID = p_device_id,
                   DEVICE_NAME = l_device_name, LAST_UPDATE_DATE = systimestamp
             where ID = p_transaction_id and EMPLOYEE_ID = p_employee_id and ORA_ROWSCN = p_expected_version;
            if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: transaction changed'); end if;
            p_entity_id := p_transaction_id;
        end if;
        select json_object('idempotency_key' value p_idempotency_key returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('TRANSACTION_MANUAL_UPSERT', 'TRANSACTION', p_entity_id, l_audit_details);
        AUDIT_PKG.complete_idempotency('TRANSACTION_MANUAL_UPSERT', p_idempotency_key, p_entity_id);
        commit;
        p_status := 'SUCCESS'; p_message := 'Manual transaction saved';
    exception when others then
        if sqlcode = -20901 then rollback; p_status := 'CONFLICT'; p_message := substr(sqlerrm, 1, 4000);
        else rejected('TRANSACTION_MANUAL_UPSERT', 'TRANSACTION', p_transaction_id, sqlerrm,
                 p_idempotency_key, p_status, p_message); end if;
    end upsert_manual_transaction;

    procedure delete_manual_transaction(
        p_transaction_id number, p_status out varchar2, p_message out varchar2
    ) is
        l_employee_id number;
        l_work_date timestamp;
    begin
        require_operator;
        select EMPLOYEE_ID, "DATE" into l_employee_id, l_work_date
          from "TRANSACTION" where ID = p_transaction_id for update;
        require_open_employee(l_employee_id, l_work_date);
        delete from "TRANSACTION" where ID = p_transaction_id;
        AUDIT_PKG.record_event('TRANSACTION_MANUAL_DELETE', 'TRANSACTION', p_transaction_id, null);
        commit;
        p_status := 'SUCCESS'; p_message := 'Manual transaction deleted';
    exception when others then
        rejected('TRANSACTION_MANUAL_DELETE', 'TRANSACTION', p_transaction_id, sqlerrm,
                 null, p_status, p_message);
    end delete_manual_transaction;

    procedure ingest_source_punches(
        p_from timestamp, p_to timestamp, p_limit number, p_result out clob
    ) is
        l_scanned number := 0;
        l_inserted number := 0;
        l_duplicates number := 0;
        l_unmatched number := 0;
        l_key varchar2(255);
        l_stage_id number;
        l_transaction_id number;
        l_employee_id number;
        l_limit number := greatest(nvl(p_limit, 1000), 0);
        l_retry boolean;
        l_error varchar2(4000);
    begin
        require_operator;
        for r in (
            select SOURCE_ID, SOURCE_USER_ID, TK, SOURCE_TIMESTAMP, DEVICE_NAME
              from V_SOURCE_PUNCH_RECENT
             where (p_from is null or SOURCE_TIMESTAMP >= p_from)
               and (p_to is null or SOURCE_TIMESTAMP < p_to)
             order by SOURCE_ID
             fetch first l_limit rows only
        ) loop
            l_scanned := l_scanned + 1;
            l_key := substr('SOURCE:' || r.SOURCE_ID || ':' || nvl(r.DEVICE_NAME, '-') || ':' ||
                            to_char(r.SOURCE_TIMESTAMP, 'YYYYMMDDHH24MISSFF6'), 1, 255);
            begin
                select ID into l_employee_id from EMPLOYEE
                 where to_char(EMPLOYEE_NUMBER) = r.SOURCE_USER_ID;
            exception when no_data_found then
                AUDIT_PKG.reserve_idempotency('TRANSACTION_SOURCE_INGEST', l_key,
                                              'TRANSACTION_STAGE', l_stage_id, l_retry);
                if l_retry then
                    l_duplicates := l_duplicates + 1;
                    continue;
                end if;
                l_unmatched := l_unmatched + 1;
                insert into TRANSACTION_STAGE (
                    EMPLOYEE_NUMBER, EVENT_TYPE, EVENT_TIME, DEVICE_NAME, IDEMPOTENCY_KEY, STATUS
                ) values (
                    r.SOURCE_USER_ID, case when r.TK = 1 then '0' else '1' end,
                    r.SOURCE_TIMESTAMP, r.DEVICE_NAME, l_key, 'UNMATCHED'
                );
                select ID into l_stage_id from TRANSACTION_STAGE where IDEMPOTENCY_KEY = l_key;
                AUDIT_PKG.complete_idempotency('TRANSACTION_SOURCE_INGEST', l_key, l_stage_id);
                continue;
            end;
            require_open_employee(l_employee_id, r.SOURCE_TIMESTAMP);
            AUDIT_PKG.reserve_idempotency('TRANSACTION_SOURCE_INGEST', l_key,
                                          'TRANSACTION_STAGE', l_stage_id, l_retry);
            if l_retry then
                l_duplicates := l_duplicates + 1;
                continue;
            end if;
            begin
                select ID into l_stage_id from TRANSACTION_STAGE where IDEMPOTENCY_KEY = l_key;
                l_duplicates := l_duplicates + 1;
            exception when no_data_found then
                begin
                    select ID into l_transaction_id from "TRANSACTION"
                     where EMPLOYEE_ID = l_employee_id
                       and TYPE = case when r.TK = 1 then '0' else '1' end
                       and "DATE" = r.SOURCE_TIMESTAMP
                       and nvl(DEVICE_NAME, chr(0)) = nvl(r.DEVICE_NAME, chr(0));
                    l_duplicates := l_duplicates + 1;
                exception when no_data_found then
                    insert into "TRANSACTION" (EMPLOYEE_ID, TYPE, "DATE", DEVICE_NAME, CREATION_DATE)
                    values (l_employee_id, case when r.TK = 1 then '0' else '1' end,
                            r.SOURCE_TIMESTAMP, r.DEVICE_NAME, systimestamp)
                    returning ID into l_transaction_id;
                    l_inserted := l_inserted + 1;
                end;
                insert into TRANSACTION_STAGE (
                    EMPLOYEE_NUMBER, EVENT_TYPE, EVENT_TIME, DEVICE_NAME, IDEMPOTENCY_KEY, STATUS
                ) values (
                    r.SOURCE_USER_ID, case when r.TK = 1 then '0' else '1' end,
                    r.SOURCE_TIMESTAMP, r.DEVICE_NAME, l_key, 'COMPLETED'
                );
            end;
            select ID into l_stage_id from TRANSACTION_STAGE where IDEMPOTENCY_KEY = l_key;
            AUDIT_PKG.complete_idempotency('TRANSACTION_SOURCE_INGEST', l_key, l_stage_id);
        end loop;
        select json_object('source' value 'V_SOURCE_PUNCH_RECENT', 'scanned' value l_scanned,
                           'inserted' value l_inserted, 'duplicates' value l_duplicates,
                           'unmatched' value l_unmatched returning clob)
          into p_result from dual;
        AUDIT_PKG.record_event('TRANSACTION_SOURCE_INGEST', 'TRANSACTION_STAGE', null, p_result);
        commit;
    exception when others then
        l_error := sqlerrm;
        rollback;
        AUDIT_PKG.record_error('TRANSACTION_SOURCE_INGEST_REJECTED', l_error, null);
        select json_object('source' value 'V_SOURCE_PUNCH_RECENT', 'status' value 'REJECTED',
                           'message' value substr(l_error, 1, 1000) returning clob)
          into p_result from dual;
    end ingest_source_punches;

    procedure sync_punches_job(
        p_lookback_hours number default 48,
        p_limit number default 50000,
        p_result out clob
    ) is
        l_scanned number := 0;
        l_inserted number := 0;
        l_duplicates number := 0;
        l_unmatched number := 0;
        l_key varchar2(255);
        l_employee_id number;
        l_limit number := greatest(nvl(p_limit, 50000), 0);
        l_cutoff timestamp with time zone;
        l_error varchar2(4000);
    begin
        l_cutoff := systimestamp - numtodsinterval(nvl(p_lookback_hours, 48), 'HOUR');
        for r in (
            select SOURCE_ID, SOURCE_USER_ID, TK, SOURCE_TIMESTAMP, DEVICE_NAME
              from V_SOURCE_PUNCH_RECENT
             where SOURCE_TIMESTAMP >= l_cutoff
             order by SOURCE_ID
             fetch first l_limit rows only
        ) loop
            l_scanned := l_scanned + 1;
            l_key := substr('SOURCE:' || r.SOURCE_ID || ':' || nvl(r.DEVICE_NAME, '-') || ':' ||
                            to_char(r.SOURCE_TIMESTAMP, 'YYYYMMDDHH24MISSFF6TZH:TZM'), 1, 255);
            begin
                select ID into l_employee_id from EMPLOYEE
                 where to_char(EMPLOYEE_NUMBER) = r.SOURCE_USER_ID
                   and IS_ACTIVE = '1';
            exception when no_data_found then
                l_unmatched := l_unmatched + 1;
                begin
                    insert into TRANSACTION_STAGE (
                        EMPLOYEE_NUMBER, EVENT_TYPE, EVENT_TIME, DEVICE_NAME, IDEMPOTENCY_KEY, STATUS
                    ) values (
                        r.SOURCE_USER_ID, case when r.TK = 1 then '0' else '1' end,
                        r.SOURCE_TIMESTAMP, r.DEVICE_NAME, l_key, 'UNMATCHED'
                    );
                exception when dup_val_on_index then
                    l_duplicates := l_duplicates + 1;
                end;
                continue;
            end;

            begin
                insert into TRANSACTION_STAGE (
                    EMPLOYEE_NUMBER, EVENT_TYPE, EVENT_TIME, DEVICE_NAME, IDEMPOTENCY_KEY, STATUS
                ) values (
                    r.SOURCE_USER_ID, case when r.TK = 1 then '0' else '1' end,
                    r.SOURCE_TIMESTAMP, r.DEVICE_NAME, l_key, 'COMPLETED'
                );
                insert into "TRANSACTION" (EMPLOYEE_ID, TYPE, "DATE", DEVICE_NAME, CREATION_DATE)
                values (l_employee_id, case when r.TK = 1 then '0' else '1' end,
                        r.SOURCE_TIMESTAMP, r.DEVICE_NAME, systimestamp);
                l_inserted := l_inserted + 1;
            exception when dup_val_on_index then
                l_duplicates := l_duplicates + 1;
            end;
        end loop;
        select json_object('source' value 'V_SOURCE_PUNCH_RECENT', 'scanned' value l_scanned,
                           'inserted' value l_inserted, 'duplicates' value l_duplicates,
                           'unmatched' value l_unmatched returning clob)
          into p_result from dual;
        AUDIT_PKG.record_event('TRANSACTION_JOB_INGEST', 'TRANSACTION_STAGE', null, p_result);
        commit;
    exception when others then
        l_error := sqlerrm;
        rollback;
        AUDIT_PKG.record_error('TRANSACTION_JOB_INGEST_ERROR', l_error, null);
        select json_object('source' value 'V_SOURCE_PUNCH_RECENT', 'status' value 'ERROR',
                           'message' value substr(l_error, 1, 1000) returning clob)
          into p_result from dual;
    end sync_punches_job;
end TRANSACTION_API_PKG;
/
