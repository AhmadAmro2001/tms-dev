
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."IMPORT_API_PKG" as
    procedure open_batch(
        p_source_name varchar2, p_idempotency_key varchar2, p_batch_id out number
    ) is
    begin
        if not (AUTH_PKG.has_role('1') or AUTH_PKG.has_role('2')) then
            AUDIT_PKG.record_rejection('IMPORT_BATCH_OPEN', 'IMPORT_BATCH', null,
                                       'Import administration requires role 1 or 2', p_idempotency_key);
            raise_application_error(-20024, 'Import administration requires role 1 or 2');
        end if;
        if p_source_name is null or p_idempotency_key is null then
            raise_application_error(-20020, 'Source name and idempotency key are required');
        end if;

        begin
            select ID into p_batch_id
              from IMPORT_BATCH
             where IDEMPOTENCY_KEY = p_idempotency_key;
        exception
            when no_data_found then
                insert into IMPORT_BATCH (SOURCE_NAME, STATUS, IDEMPOTENCY_KEY, ACCEPTED_COUNT,
                                          REJECTED_COUNT, ERROR_COUNT)
                values (substr(p_source_name, 1, 255), 'OPEN', substr(p_idempotency_key, 1, 255),
                        0, 0, 0)
                returning ID into p_batch_id;
        end;
        AUDIT_PKG.record_event('IMPORT_BATCH_OPENED', 'IMPORT_BATCH', p_batch_id, null);
        commit;
    end open_batch;

    procedure get_batch_status(p_batch_id number, p_result out clob) is
    begin
        select json_object(
                   'batch_id' value ID,
                   'source_name' value SOURCE_NAME,
                   'status' value STATUS,
                   'accepted_count' value ACCEPTED_COUNT,
                   'rejected_count' value REJECTED_COUNT,
                   'error_count' value ERROR_COUNT
                   returning clob)
          into p_result
          from IMPORT_BATCH
         where ID = p_batch_id;
    exception
        when no_data_found then
            raise_application_error(-20021, 'Import batch not found');
    end get_batch_status;

    function parse_timestamp_value(p_value varchar2) return timestamp is
    begin
        if p_value is null then
            return null;
        end if;
        begin
            return to_timestamp(p_value, 'YYYY-MM-DD"T"HH24:MI:SS');
        exception when others then
            return to_timestamp(p_value, 'YYYY-MM-DD');
        end;
    end parse_timestamp_value;

    function parse_time_on_date(p_date timestamp, p_value varchar2) return timestamp is
    begin
        if p_date is null or p_value is null then
            return null;
        end if;
        return to_timestamp(
            to_char(p_date, 'YYYY-MM-DD') || ' ' || substr(p_value, 1, 5),
            'YYYY-MM-DD HH24:MI'
        );
    end parse_time_on_date;

    procedure process_rows(
        p_batch_id number, p_entity_type varchar2, p_rows_json clob, p_result out clob
    ) is
        l_source_name IMPORT_BATCH.SOURCE_NAME%type;
        l_status IMPORT_BATCH.STATUS%type;
        l_entity varchar2(30) := upper(trim(p_entity_type));
        l_accepted number := 0;
        l_rejected number := 0;
        l_errors number := 0;
        l_row_number number := 0;
        l_employee_id number;
        l_employee_number number;
        l_from_date timestamp;
        l_to_date timestamp;
        l_work_date timestamp;
        l_from_time timestamp;
        l_to_time timestamp;
        l_type_id number;
        l_count number;
        l_error varchar2(4000);
        l_can_write boolean;
        l_event_id number;
        l_event_status varchar2(30);
        l_event_message varchar2(4000);
        l_row_rejected boolean;

        procedure reject_row(p_message varchar2, p_code varchar2 := 'VALIDATION_ERROR') is
        begin
            insert into IMPORT_ERROR (BATCH_ID, ROW_NUMBER, ERROR_CODE, ERROR_MESSAGE)
            values (p_batch_id, l_row_number, substr(p_code, 1, 100), substr(p_message, 1, 4000));
            l_rejected := l_rejected + 1;
            l_errors := l_errors + 1;
            l_row_rejected := true;
        end reject_row;

        procedure require_write(p_feature varchar2) is
        begin
            if not AUTH_PKG.can_write(p_feature) then
                raise_application_error(-20025, 'Import write access is not granted for ' || p_feature);
            end if;
        end require_write;
    begin
        if p_batch_id is null or p_rows_json is null or l_entity not in
           ('EMPLOYEES', 'VACATIONS', 'MISSIONS', 'TRAININGS', 'PERMISSIONS') then
            raise_application_error(-20022, 'Valid batch, JSON rows, and entity type are required');
        end if;

        select SOURCE_NAME, STATUS into l_source_name, l_status
          from IMPORT_BATCH where ID = p_batch_id for update;
        if l_status not in ('OPEN', 'RETRY') then
            raise_application_error(-20023, 'Import batch is not open for processing');
        end if;

        if l_entity = 'EMPLOYEES' then
            require_write('WriteEmployees');
        elsif l_entity = 'VACATIONS' then
            require_write('WriteVacations');
        elsif l_entity = 'MISSIONS' then
            require_write('WriteMissions');
        elsif l_entity = 'TRAININGS' then
            require_write('WriteTrainings');
        else
            require_write('WritePermissions');
        end if;

        for r in (
            select row_number() over (order by 1) as rn,
                   employee_number, name, project_id, location_id, department_id,
                   grade_id, nationality, religion, print_timesheet,
                   from_date, to_date, work_date, from_time, to_time,
                   type_code, description
              from json_table(
                       p_rows_json, '$[*]' columns (
                           employee_number varchar2(100) path '$.employee_number',
                           name            varchar2(4000) path '$.name',
                           project_id      number path '$.project_id',
                           location_id     number path '$.location_id',
                           department_id   number path '$.department_id',
                           grade_id        number path '$.grade_id',
                           nationality     varchar2(4000) path '$.nationality',
                           religion        varchar2(4000) path '$.religion',
                           print_timesheet varchar2(10) path '$.print_timesheet',
                           from_date       varchar2(100) path '$.from_date',
                           to_date         varchar2(100) path '$.to_date',
                           work_date       varchar2(100) path '$.work_date',
                           from_time       varchar2(100) path '$.from_time',
                           to_time         varchar2(100) path '$.to_time',
                           type_code       varchar2(100) path '$.type_code',
                           description     varchar2(4000) path '$.description'
                       )
                   )
        ) loop
            l_row_number := r.rn;
            l_row_rejected := false;
            begin
                l_employee_number := to_number(r.employee_number);
                if l_entity = 'EMPLOYEES' then
                    if l_employee_number is null or r.name is null or r.location_id is null then
                        reject_row('employee_number, name, and location_id are required');
                    elsif not AUTH_PKG.can_access_location(r.location_id) then
                        reject_row('Employee location is out of scope', 'LOCATION_DENIED');
                    else
                        select count(*) into l_count from LOCATION where ID=r.location_id;
                        if l_count <> 1 then
                            reject_row('Employee location was not found', 'REFERENCE_NOT_FOUND');
                        else
                        if r.project_id is not null then
                            select count(*) into l_count from PROJECT where ID=r.project_id;
                            if l_count <> 1 then reject_row('Employee project was not found', 'REFERENCE_NOT_FOUND'); end if;
                        end if;
                        if r.department_id is not null then
                            select count(*) into l_count from DEPARTMENT where ID=r.department_id;
                            if l_count <> 1 then reject_row('Employee department was not found', 'REFERENCE_NOT_FOUND'); end if;
                        end if;
                        if r.grade_id is not null then
                            select count(*) into l_count from GRADE where ID=r.grade_id;
                            if l_count <> 1 then reject_row('Employee grade was not found', 'REFERENCE_NOT_FOUND'); end if;
                        end if;
                        if l_row_rejected then
                            null;
                        else
                        select count(*) into l_count from EMPLOYEE where EMPLOYEE_NUMBER = l_employee_number;
                        if l_count > 0 then
                        reject_row('Employee number already exists', 'DUPLICATE_EMPLOYEE');
                        else
                        insert into EMPLOYEE (
                            EMPLOYEE_NUMBER, NAME, PROJECT_ID, LOCATION_ID, DEPARTMENT_ID,
                            IS_ACTIVE, GRADE_ID, NATIONALITY, RELIGION, PRINT_TIMESHEET,
                            CREATION_DATE
                        ) values (
                            l_employee_number, r.name, r.project_id, r.location_id, r.department_id,
                            '1', r.grade_id, r.nationality, r.religion,
                            case when upper(nvl(r.print_timesheet, 'Y')) in ('N', '0', 'FALSE') then '0' else '1' end,
                            systimestamp
                        );
                        l_accepted := l_accepted + 1;
                        end if;
                        end if;
                        end if;
                    end if;
                else
                    select ID into l_employee_id from EMPLOYEE
                     where EMPLOYEE_NUMBER = l_employee_number and IS_ACTIVE = '1';
                    l_from_date := parse_timestamp_value(r.from_date);
                    l_to_date := parse_timestamp_value(r.to_date);
                    l_work_date := parse_timestamp_value(r.work_date);
                    if l_entity in ('VACATIONS', 'MISSIONS', 'TRAININGS') then
                        if l_from_date is null or l_to_date is null or l_from_date > l_to_date then
                            reject_row('Valid from_date and to_date are required');
                        elsif l_entity = 'VACATIONS' then
                            select ID into l_type_id from VACATION_TYPE
                             where upper(CODE) = upper(r.type_code) and nvl(IS_ARCHIVE, '0') <> '1';
                            EVENT_API_PKG.upsert_event('VACATION', null, l_employee_id, l_from_date, l_to_date,
                                l_type_id, r.description, null, 'IMPORT:'||p_batch_id||':'||l_row_number,
                                l_event_id, l_event_status, l_event_message);
                            if l_event_status in ('SUCCESS','IDEMPOTENT') then l_accepted:=l_accepted+1; else reject_row(l_event_message,'EVENT_REJECTED'); end if;
                        elsif l_entity = 'MISSIONS' then
                            EVENT_API_PKG.upsert_event('MISSION', null, l_employee_id, l_from_date, l_to_date,
                                null, r.description, null, 'IMPORT:'||p_batch_id||':'||l_row_number,
                                l_event_id, l_event_status, l_event_message);
                            if l_event_status in ('SUCCESS','IDEMPOTENT') then l_accepted:=l_accepted+1; else reject_row(l_event_message,'EVENT_REJECTED'); end if;
                        else
                            EVENT_API_PKG.upsert_event('TRAINING', null, l_employee_id, l_from_date, l_to_date,
                                null, r.description, null, 'IMPORT:'||p_batch_id||':'||l_row_number,
                                l_event_id, l_event_status, l_event_message);
                            if l_event_status in ('SUCCESS','IDEMPOTENT') then l_accepted:=l_accepted+1; else reject_row(l_event_message,'EVENT_REJECTED'); end if;
                        end if;
                    else
                        l_from_time := parse_time_on_date(l_work_date, r.from_time);
                        l_to_time := parse_time_on_date(l_work_date, r.to_time);
                        if l_work_date is null or l_from_time is null or l_to_time is null
                           or l_from_time >= l_to_time then
                            reject_row('Valid work_date, from_time, and to_time are required');
                        else
                            select ID into l_type_id from PERMISSION_TYPE
                             where upper(CODE) = upper(r.type_code) or upper(NAME) = upper(r.type_code);
                            EVENT_API_PKG.upsert_event('PERMISSION', null, l_employee_id, l_from_time, l_to_time,
                                l_type_id, r.description, null, 'IMPORT:'||p_batch_id||':'||l_row_number,
                                l_event_id, l_event_status, l_event_message);
                            if l_event_status in ('SUCCESS','IDEMPOTENT') then l_accepted:=l_accepted+1; else reject_row(l_event_message,'EVENT_REJECTED'); end if;
                        end if;
                    end if;
                end if;
            exception
                when no_data_found then
                    reject_row('Referenced employee or type was not found', 'REFERENCE_NOT_FOUND');
                when value_error then
                    reject_row('Invalid numeric or date value', 'INVALID_VALUE');
                when others then
                    reject_row(substr(sqlerrm, 1, 4000), 'ROW_ERROR');
            end;
        end loop;

        update IMPORT_BATCH
           set STATUS = 'COMPLETED',
               ACCEPTED_COUNT = nvl(ACCEPTED_COUNT, 0) + l_accepted,
               REJECTED_COUNT = nvl(REJECTED_COUNT, 0) + l_rejected,
               ERROR_COUNT = nvl(ERROR_COUNT, 0) + l_errors
         where ID = p_batch_id;
        AUDIT_PKG.record_event('IMPORT_BATCH_PROCESSED', 'IMPORT_BATCH', p_batch_id,
                               json_object('entity_type' value l_entity,
                                           'accepted' value l_accepted,
                                           'rejected' value l_rejected));
        commit;
        select json_object('batch_id' value p_batch_id, 'entity_type' value l_entity,
                           'accepted' value l_accepted, 'rejected' value l_rejected,
                           'errors' value l_errors returning clob)
          into p_result from dual;
    exception
        when no_data_found then
            rollback;
            AUDIT_PKG.record_rejection('IMPORT_BATCH_PROCESS', 'IMPORT_BATCH', p_batch_id,
                                       'Import batch or referenced data not found', null);
            raise_application_error(-20021, 'Import batch or referenced data not found');
        when others then
            rollback;
            AUDIT_PKG.record_rejection('IMPORT_BATCH_PROCESS', 'IMPORT_BATCH', p_batch_id,
                                       sqlerrm, null);
            raise;
    end process_rows;
end IMPORT_API_PKG;
/
