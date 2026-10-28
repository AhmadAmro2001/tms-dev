
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."IMPORT_API_PKG" as
    /* Opens or reuses a batch using the supplied idempotency key. */
    procedure open_batch(
        p_source_name varchar2, p_idempotency_key varchar2, p_batch_id out number
    );
    /* Returns batch state and accepted, rejected, and error counters as JSON. */
    procedure get_batch_status(p_batch_id number, p_result out clob);
    /* Processes a normalized JSON array for EMPLOYEES, VACATIONS, MISSIONS,
       TRAININGS, or PERMISSIONS. Invalid rows are retained in IMPORT_ERROR. */
    procedure process_rows(
        p_batch_id number, p_entity_type varchar2, p_rows_json clob, p_result out clob
    );
end IMPORT_API_PKG;
/
