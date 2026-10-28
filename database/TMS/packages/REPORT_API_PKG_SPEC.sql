
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."REPORT_API_PKG" as
    /* Returns dashboard KPI rows for the current application scope. */
    procedure get_dashboard(p_rows out sys_refcursor);
    /* Returns employee attendance summary rows for the requested period. */
    procedure get_employee_summary(p_employee_id number, p_from timestamp, p_to timestamp,
                                   p_rows out sys_refcursor);
    /* Compares local transaction counts with unmatched source punch counts. */
    procedure get_transaction_source_audit(p_from timestamp, p_to timestamp,
                                           p_rows out sys_refcursor);
    /* Returns transaction workload grouped by device. */
    procedure get_device_workload(p_from timestamp, p_to timestamp, p_rows out sys_refcursor);
    /* Returns the controlled export manifest; export execution remains an APEX concern. */
    procedure get_export_manifest(p_report_code varchar2, p_filters_json clob, p_result out clob);
    /* Probes the BioStar source-punch database link with a lightweight read; returns 1/0. */
    function source_link_available_sql return number;
    /* Returns query text for the punch monitor report; falls back to a zero-row query when the source link is unavailable. */
    function get_punch_monitor_sql return varchar2;
    /* Returns query text for the unmatched-punch report; falls back to a zero-row query when the source link is unavailable. */
    function get_unmatched_punch_sql return varchar2;
    /* Returns query text for the transaction/source audit comparison; degrades the remote branch when the source link is unavailable. */
    function get_source_audit_sql return varchar2;
    /* Returns query text for the device workload report with a bound date range. */
    function get_device_workload_sql return varchar2;
end REPORT_API_PKG;
/
