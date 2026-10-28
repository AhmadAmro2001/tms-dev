
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."DEVICE_API_PKG" as
    /* Returns registered devices optionally restricted to a location. */
    procedure get_devices(p_location_id number, p_rows out sys_refcursor);
    /* Returns pending device upload requests optionally restricted to a location. */
    procedure get_upload_requests(p_location_id number, p_rows out sys_refcursor);
    /* Returns device activity within an optional timestamp range. */
    procedure get_device_activity(p_from timestamp, p_to timestamp, p_rows out sys_refcursor);
    procedure upsert_device(
        p_device_id number, p_name varchar2, p_ip varchar2, p_port number,
        p_communication_key number, p_type number, p_location_id number,
        p_entity_id out number, p_status out varchar2, p_message out varchar2
    );
    procedure delete_device(p_device_id number, p_status out varchar2, p_message out varchar2);
    /* Correct local activity watermarks only; this never claims adapter execution. */
    procedure correct_activity_timestamps(
        p_device_id number, p_last_downloaded timestamp, p_last_transaction timestamp,
        p_status out varchar2, p_message out varchar2
    );
    procedure enqueue_command(
        p_device_id number, p_command_type varchar2, p_payload_json clob,
        p_idempotency_key varchar2, p_queue_id out number,
        p_status out varchar2, p_message out varchar2
    );
    procedure transition_command(
        p_queue_id number, p_new_status varchar2, p_adapter_receipt varchar2,
        p_status out varchar2, p_message out varchar2
    );
end DEVICE_API_PKG;
/
