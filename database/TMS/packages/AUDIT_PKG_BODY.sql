
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."AUDIT_PKG" as
    function current_app_user_id return number is
        l_app_user_id number;
    begin
        select ID into l_app_user_id
          from APP_USER
         where upper(APEX_USERNAME) = upper(sys_context('APEX$SESSION', 'APP_USER'))
           and ENABLED = 'Y';
        return l_app_user_id;
    exception
        when no_data_found then return null;
    end current_app_user_id;

    procedure record_event(
        p_event_code varchar2,
        p_entity_type varchar2,
        p_entity_id number,
        p_details_json clob
    ) is
        l_app_user_id number := current_app_user_id;
    begin
        insert into AUDIT_EVENT (
            APP_USER_ID, EVENT_CODE, ENTITY_TYPE, ENTITY_ID, CORRELATION_ID,
            SUCCESS_FLAG, DETAILS_JSON
        ) values (
            l_app_user_id, substr(p_event_code, 1, 100), substr(p_entity_type, 1, 100),
            p_entity_id, sys_context('USERENV', 'CLIENT_IDENTIFIER'), 'Y', p_details_json
        );
    end record_event;

    procedure record_error(
        p_error_code varchar2,
        p_message varchar2,
        p_details_json clob
    ) is
        pragma autonomous_transaction;
    begin
        insert into AUDIT_EVENT (
            EVENT_CODE, CORRELATION_ID, SUCCESS_FLAG, DETAILS_JSON
        ) values (
            substr(p_error_code, 1, 100), sys_context('USERENV', 'CLIENT_IDENTIFIER'), 'N',
            json_object(
                'message' value substr(p_message, 1, 1000),
                'details' value p_details_json format json
                returning clob
            )
        );
        commit;
    end record_error;

    procedure record_rejection(
        p_operation varchar2,
        p_entity_type varchar2,
        p_entity_id number,
        p_message varchar2,
        p_idempotency_key varchar2 default null
    ) is
        pragma autonomous_transaction;
        l_app_user_id number := current_app_user_id;
    begin
        insert into AUDIT_EVENT (
            APP_USER_ID, EVENT_CODE, ENTITY_TYPE, ENTITY_ID, CORRELATION_ID,
            SUCCESS_FLAG, DETAILS_JSON
        ) values (
            l_app_user_id, substr(p_operation || '_REJECTED', 1, 100),
            substr(p_entity_type, 1, 100), p_entity_id,
            sys_context('USERENV', 'CLIENT_IDENTIFIER'), 'N',
            json_object(
                'message' value substr(p_message, 1, 1000),
                'idempotency_key' value substr(p_idempotency_key, 1, 255)
                returning clob
            )
        );
        commit;
    end record_rejection;

    procedure reserve_idempotency(
        p_operation_code varchar2, p_idempotency_key varchar2,
        p_entity_type varchar2, p_entity_id out number, p_is_retry out boolean
    ) is
    begin
        if p_operation_code is null or p_idempotency_key is null then
            raise_application_error(-20100, 'Operation code and idempotency key are required');
        end if;
        insert into WRITE_IDEMPOTENCY (OPERATION_CODE, IDEMPOTENCY_KEY, ENTITY_TYPE, STATUS)
        values (substr(p_operation_code, 1, 100), substr(p_idempotency_key, 1, 255),
                substr(p_entity_type, 1, 100), 'PENDING');
        p_entity_id := null;
        p_is_retry := false;
    exception
        when dup_val_on_index then
            select ENTITY_ID into p_entity_id
              from WRITE_IDEMPOTENCY
             where OPERATION_CODE = substr(p_operation_code, 1, 100)
               and IDEMPOTENCY_KEY = substr(p_idempotency_key, 1, 255)
               and STATUS = 'COMPLETED';
            p_is_retry := true;
    end reserve_idempotency;

    procedure complete_idempotency(
        p_operation_code varchar2, p_idempotency_key varchar2, p_entity_id number
    ) is
    begin
        update WRITE_IDEMPOTENCY
           set ENTITY_ID = p_entity_id, STATUS = 'COMPLETED'
         where OPERATION_CODE = substr(p_operation_code, 1, 100)
           and IDEMPOTENCY_KEY = substr(p_idempotency_key, 1, 255)
           and STATUS = 'PENDING';
        if sql%rowcount <> 1 then
            raise_application_error(-20101, 'Idempotency reservation was not pending');
        end if;
    end complete_idempotency;
end AUDIT_PKG;
/
