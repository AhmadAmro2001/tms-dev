
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."AUDIT_PKG" as
    /* Records a successful business event without exposing protected data. */
    procedure record_event(
        p_event_code varchar2,
        p_entity_type varchar2,
        p_entity_id number,
        p_details_json clob
    );
    /* Records a failed operation and its diagnostic details. */
    procedure record_error(
        p_error_code varchar2,
        p_message varchar2,
        p_details_json clob
    );
    /* Records a rejected package operation without leaking its input payload. */
    procedure record_rejection(
        p_operation varchar2,
        p_entity_type varchar2,
        p_entity_id number,
        p_message varchar2,
        p_idempotency_key varchar2 default null
    );
    procedure reserve_idempotency(
        p_operation_code varchar2, p_idempotency_key varchar2,
        p_entity_type varchar2, p_entity_id out number, p_is_retry out boolean
    );
    procedure complete_idempotency(
        p_operation_code varchar2, p_idempotency_key varchar2, p_entity_id number
    );
end AUDIT_PKG;
/
