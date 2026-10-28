
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."DEVICE_API_PKG" as
    procedure require_operator is
    begin
        if not AUTH_PKG.has_role('1') or not AUTH_PKG.can_write('Devices') then
            raise_application_error(-20140, 'Device administration requires role 1 and Devices write access');
        end if;
    end require_operator;

    procedure rejected(p_operation varchar2, p_entity_type varchar2, p_entity_id number,
                       p_error varchar2, p_key varchar2, p_status out varchar2,
                       p_message out varchar2) is
    begin
        rollback;
        p_status := 'REJECTED';
        p_message := substr(p_error, 1, 4000);
        AUDIT_PKG.record_rejection(p_operation, p_entity_type, p_entity_id, p_message, p_key);
    end rejected;

    procedure get_devices(p_location_id number, p_rows out sys_refcursor) is
    begin
        open p_rows for select * from V_DEVICE_ACTIVITY
        where (p_location_id is null or LOCATION_ID = p_location_id)
          and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1
        order by DEVICE_NAME;
    end get_devices;

    procedure get_upload_requests(p_location_id number, p_rows out sys_refcursor) is
    begin
        open p_rows for select DEVICE_ID, DEVICE_NAME, LOCATION_ID
        from V_DEVICE_ACTIVITY
        where IS_PENDING_REQUEST = 'Y'
          and (p_location_id is null or LOCATION_ID = p_location_id)
        order by DEVICE_NAME;
    end get_upload_requests;

    procedure get_device_activity(p_from timestamp, p_to timestamp, p_rows out sys_refcursor) is
    begin
        open p_rows for select * from V_DEVICE_ACTIVITY
        where (p_from is null or LAST_TRANSACTION >= p_from)
          and (p_to is null or LAST_TRANSACTION < p_to)
        order by LAST_TRANSACTION desc nulls last;
    end get_device_activity;

    procedure upsert_device(
        p_device_id number, p_name varchar2, p_ip varchar2, p_port number,
        p_communication_key number, p_type number, p_location_id number,
        p_entity_id out number, p_status out varchar2, p_message out varchar2
    ) is
    begin
        require_operator;
        if p_name is null or p_ip is null or p_port is null or p_location_id is null
           or not AUTH_PKG.can_access_location(p_location_id) then
            raise_application_error(-20141, 'A permitted location, name, IP address, and port are required');
        end if;
        if not regexp_like(trim(p_ip), '^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$') then
            raise_application_error(-20150, 'Device IP address must be a valid IPv4 address');
        end if;
        if p_port < 0 or p_port > 65535 then
            raise_application_error(-20151, 'Device port must be between 0 and 65535');
        end if;
        if p_type is null or p_type not between 0 and 2 then
            raise_application_error(-20152, 'Device type must be 0, 1, or 2');
        end if;
        if p_device_id is null then
            insert into DEVICE (NAME, IP, PORT, COMMUNICATION_KEY, TYPE, LOCATION_ID,
                                LAST_DOWNLOADED, LAST_TRANSACTION, IS_PENDING_REQUEST,
                                HAS_LAST_REQUEST_FAILED, PENDING_REQUEST_TIME)
            values (p_name, p_ip, p_port, nvl(p_communication_key, 0), p_type, p_location_id,
                    timestamp '1900-01-01 00:00:00', timestamp '1900-01-01 00:00:00', '0',
                    '0', timestamp '1900-01-01 00:00:00')
            returning ID into p_entity_id;
        else
            update DEVICE
               set NAME = p_name, IP = p_ip, PORT = p_port,
                   COMMUNICATION_KEY = nvl(p_communication_key, 0), TYPE = p_type,
                   LOCATION_ID = p_location_id, IS_PENDING_REQUEST = '0',
                   HAS_LAST_REQUEST_FAILED = '0', PENDING_REQUEST_TIME = timestamp '1900-01-01 00:00:00'
             where ID = p_device_id
               and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1;
            if sql%rowcount <> 1 then raise_application_error(-20142, 'Device was not found or is out of scope'); end if;
            p_entity_id := p_device_id;
        end if;
        AUDIT_PKG.record_event('DEVICE_UPSERT', 'DEVICE', p_entity_id, null);
        commit;
        p_status := 'SUCCESS'; p_message := 'Device saved';
    exception when others then
        rejected('DEVICE_UPSERT', 'DEVICE', p_device_id, sqlerrm, null, p_status, p_message);
    end upsert_device;

    procedure delete_device(p_device_id number, p_status out varchar2, p_message out varchar2) is
    begin
        require_operator;
        delete from DEVICE
         where ID = p_device_id and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1;
        if sql%rowcount <> 1 then raise_application_error(-20143, 'Device was not found or is out of scope'); end if;
        AUDIT_PKG.record_event('DEVICE_DELETE', 'DEVICE', p_device_id, null);
        commit;
        p_status := 'SUCCESS'; p_message := 'Device deleted';
    exception when others then
        rejected('DEVICE_DELETE', 'DEVICE', p_device_id, sqlerrm, null, p_status, p_message);
    end delete_device;

    procedure correct_activity_timestamps(
        p_device_id number, p_last_downloaded timestamp, p_last_transaction timestamp,
        p_status out varchar2, p_message out varchar2
    ) is
    begin
        require_operator;
        if p_device_id is null or p_last_downloaded is null or p_last_transaction is null then
            raise_application_error(-20153, 'Device and both activity timestamps are required');
        end if;
        update DEVICE
           set LAST_DOWNLOADED = p_last_downloaded,
               LAST_TRANSACTION = p_last_transaction,
               IS_PENDING_REQUEST = '0',
               HAS_LAST_REQUEST_FAILED = '0',
               PENDING_REQUEST_TIME = timestamp '1900-01-01 00:00:00'
         where ID = p_device_id
           and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1;
        if sql%rowcount <> 1 then
            raise_application_error(-20154, 'Device was not found or is out of scope');
        end if;
        AUDIT_PKG.record_event('DEVICE_ACTIVITY_TIMESTAMPS_CORRECTED', 'DEVICE', p_device_id, null);
        commit;
        p_status := 'SUCCESS'; p_message := 'Device activity timestamps corrected';
    exception when others then
        rejected('DEVICE_ACTIVITY_TIMESTAMPS_CORRECTED', 'DEVICE', p_device_id, sqlerrm, null, p_status, p_message);
    end correct_activity_timestamps;

    procedure enqueue_command(
        p_device_id number, p_command_type varchar2, p_payload_json clob,
        p_idempotency_key varchar2, p_queue_id out number,
        p_status out varchar2, p_message out varchar2
    ) is
        l_payload clob;
        l_audit_details clob;
        l_count number;
        l_retry boolean;
    begin
        require_operator;
        if p_device_id is null or p_command_type is null or p_idempotency_key is null then
            raise_application_error(-20144, 'In-scope device, command type, and idempotency key are required');
        end if;
        select count(*) into l_count from DEVICE
         where ID = p_device_id and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1;
        if l_count <> 1 then
            raise_application_error(-20145, 'Device was not found or is out of scope');
        end if;
        if dbms_lob.instr(lower(p_payload_json), 'password')>0
           or dbms_lob.instr(lower(p_payload_json), 'secret')>0
           or dbms_lob.instr(lower(p_payload_json), 'token')>0
           or dbms_lob.instr(lower(p_payload_json), 'credential')>0 then
            raise_application_error(-20148, 'Device command payload contains a protected credential field');
        end if;
        AUDIT_PKG.reserve_idempotency('DEVICE_COMMAND', p_idempotency_key, 'COMMAND_QUEUE', p_queue_id, l_retry);
        if l_retry then
            p_status := 'IDEMPOTENT'; p_message := 'Existing pending command was returned'; return;
        end if;
        select json_object(
                   'device_id' value p_device_id,
                   'idempotency_key' value substr(p_idempotency_key, 1, 255),
                   'payload' value p_payload_json format json returning clob
               ) into l_payload from dual;
        insert into COMMAND_QUEUE (COMMAND_TYPE, PAYLOAD_JSON, STATUS, CREATED_BY)
        values (substr(upper(p_command_type), 1, 100), l_payload, 'PENDING',
                sys_context('APEX$SESSION', 'APP_USER'))
        returning ID into p_queue_id;
        select json_object('device_id' value p_device_id,
                           'command_type' value upper(p_command_type) returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('DEVICE_COMMAND_QUEUED', 'COMMAND_QUEUE', p_queue_id, l_audit_details);
        AUDIT_PKG.complete_idempotency('DEVICE_COMMAND', p_idempotency_key, p_queue_id);
        commit;
        p_status := 'SUCCESS'; p_message := 'Command queued; no physical completion is implied';
    exception when others then
        rejected('DEVICE_COMMAND', 'COMMAND_QUEUE', p_queue_id, sqlerrm, p_idempotency_key, p_status, p_message);
    end enqueue_command;

    procedure transition_command(
        p_queue_id number, p_new_status varchar2, p_adapter_receipt varchar2,
        p_status out varchar2, p_message out varchar2
    ) is
        l_old_status COMMAND_QUEUE.STATUS%type;
        l_new_status varchar2(30) := upper(trim(p_new_status));
        l_device_id number;
        l_location_id number;
        l_receipt_json clob;
        l_audit_details clob;
    begin
        require_operator;
        select STATUS, json_value(PAYLOAD_JSON, '$.device_id' returning number)
          into l_old_status, l_device_id from COMMAND_QUEUE where ID = p_queue_id for update;
        select LOCATION_ID into l_location_id from DEVICE where ID = l_device_id;
        if l_device_id is null or not AUTH_PKG.can_access_location(l_location_id) then
            raise_application_error(-20149, 'Queued device was not found or is out of scope');
        end if;
        if l_old_status <> 'PENDING' or l_new_status not in ('COMPLETED', 'FAILED', 'CANCELLED') then
            raise_application_error(-20146, 'Only pending commands may transition to a terminal state');
        end if;
        if l_new_status in ('COMPLETED', 'FAILED') and trim(p_adapter_receipt) is null then
            raise_application_error(-20147, 'Adapter receipt is required for completed or failed device commands');
        end if;
        select json_object('adapter_receipt_present' value case when p_adapter_receipt is null then 'N' else 'Y' end,
                           'adapter_receipt_length' value case when p_adapter_receipt is null then 0 else length(p_adapter_receipt) end
                           returning clob)
          into l_receipt_json from dual;
        update COMMAND_QUEUE
           set STATUS = l_new_status,
               PAYLOAD_JSON = json_mergepatch(PAYLOAD_JSON, l_receipt_json)
         where ID = p_queue_id;
        select json_object('command_status' value l_new_status,
                           'adapter_receipt_present' value case when p_adapter_receipt is null then 'N' else 'Y' end,
                           'adapter_receipt_length' value case when p_adapter_receipt is null then 0 else length(p_adapter_receipt) end
                           returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('DEVICE_COMMAND_' || l_new_status, 'COMMAND_QUEUE', p_queue_id, l_audit_details);
        commit;
        p_status := 'SUCCESS'; p_message := 'Command state updated';
    exception when others then
        rejected('DEVICE_COMMAND_TRANSITION', 'COMMAND_QUEUE', p_queue_id, sqlerrm, null, p_status, p_message);
    end transition_command;
end DEVICE_API_PKG;
/
