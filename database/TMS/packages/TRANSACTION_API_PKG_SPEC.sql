
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."TRANSACTION_API_PKG" as
    /* Returns matched attendance transactions by employee, date range, and location. */
    procedure get_transactions(
        p_employee_number varchar2, p_from timestamp, p_to timestamp,
        p_location_id number, p_rows out sys_refcursor
    );
    /* Returns source punches that could not be matched to a local employee. */
    procedure get_unmatched_punches(p_from timestamp, p_to timestamp, p_rows out sys_refcursor);
    /* Validates a transaction payload and returns the source-route processing result. */
    procedure stage_transactions(p_batch_id number, p_payload clob, p_result out clob);
    procedure upsert_manual_transaction(
        p_transaction_id number, p_employee_id number, p_event_type char,
        p_event_time timestamp, p_device_id number, p_device_name varchar2,
        p_expected_version number, p_idempotency_key varchar2, p_entity_id out number,
        p_status out varchar2, p_message out varchar2
    );
    procedure delete_manual_transaction(
        p_transaction_id number, p_status out varchar2, p_message out varchar2
    );
    procedure ingest_source_punches(
        p_from timestamp, p_to timestamp, p_limit number, p_result out clob
    );
    procedure sync_punches_job(
        p_lookback_hours number default 48,
        p_limit number default 50000,
        p_result out clob
    );
end TRANSACTION_API_PKG;
/
