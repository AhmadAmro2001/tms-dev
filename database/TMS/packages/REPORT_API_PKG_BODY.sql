
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."REPORT_API_PKG" as
    procedure get_dashboard(p_rows out sys_refcursor) is
    begin
        open p_rows for select * from V_DASHBOARD_SUMMARY;
    end get_dashboard;

    procedure get_employee_summary(p_employee_id number, p_from timestamp, p_to timestamp,
                                   p_rows out sys_refcursor) is
        l_location_csv varchar2(4000) := AUTH_PKG.accessible_location_ids_csv;
    begin
        open p_rows for
            select * from V_EMPLOYEE_TRANSACTION_SUMMARY
             where (p_employee_id is null or EMPLOYEE_ID = p_employee_id)
               and LOCATION_ID in (select to_number(column_value) from table(apex_string.split(l_location_csv, ':')))
               and (p_from is null or WORK_DATE >= trunc(p_from))
               and (p_to is null or WORK_DATE < trunc(p_to))
             order by WORK_DATE desc nulls last, EMPLOYEE_NUMBER;
    end get_employee_summary;

    procedure get_transaction_source_audit(p_from timestamp, p_to timestamp,
                                           p_rows out sys_refcursor) is
        l_location_csv varchar2(4000) := AUTH_PKG.accessible_location_ids_csv;
    begin
        open p_rows for
            select 'LOCAL_TRANSACTION' as SOURCE_TYPE, count(*) as ROW_COUNT,
                   min(t."DATE") as FIRST_DATE, max(t."DATE") as LAST_DATE
              from "TRANSACTION" t join EMPLOYEE e on e.ID = t.EMPLOYEE_ID
             where e.LOCATION_ID in (select to_number(column_value) from table(apex_string.split(l_location_csv, ':')))
               and (p_from is null or t."DATE" >= p_from)
               and (p_to is null or t."DATE" < p_to)
            union all
            select 'UNMATCHED_SOURCE_PUNCH', count(*), min(SOURCE_TIMESTAMP), max(SOURCE_TIMESTAMP)
              from V_UNMATCHED_PUNCH
             where (p_from is null or SOURCE_TIMESTAMP >= p_from)
               and (p_to is null or SOURCE_TIMESTAMP < p_to);
    end get_transaction_source_audit;

    procedure get_device_workload(p_from timestamp, p_to timestamp, p_rows out sys_refcursor) is
    begin
        open p_rows for
            select d.ID as DEVICE_ID, d.NAME as DEVICE_NAME, d.LOCATION_ID,
                   count(t.ID) as TRANSACTION_COUNT,
                   min(t."DATE") as FIRST_TRANSACTION, max(t."DATE") as LAST_TRANSACTION
              from DEVICE d
              left join "TRANSACTION" t on t.DEVICE_ID = d.ID
             and (p_from is null or t."DATE" >= p_from)
             and (p_to is null or t."DATE" < p_to)
             group by d.ID, d.NAME, d.LOCATION_ID
             order by TRANSACTION_COUNT desc, d.NAME;
    end get_device_workload;

    procedure get_export_manifest(p_report_code varchar2, p_filters_json clob, p_result out clob) is
    begin
        select json_object(
                   'report_code' value p_report_code,
                   'format' value 'APEX_NATIVE_EXPORT',
                   'filters' value p_filters_json format json,
                   'remote_write' value false
                   returning clob)
          into p_result
          from dual;
    end get_export_manifest;

    function source_link_available_sql return number is
        l_probe number;
    begin
        select count(*) into l_probe from V_SOURCE_PUNCH_RECENT where rownum = 1;
        return 1;
    exception
        when others then
            return 0;
    end source_link_available_sql;

    function get_punch_monitor_sql return varchar2 is
    begin
        if source_link_available_sql = 1 then
            return 'select SOURCE_ID, SOURCE_USER_ID, TK, SOURCE_TIMESTAMP, DEVICE_NAME'
                || ' from V_PUNCH_EMPLOYEE_MATCH'
                || ' where AUTH_PKG.can_read_sql(''ReadTransactions'') = 1'
                || ' and (:P900_FROM_DATE is null or SOURCE_TIMESTAMP >= :P900_FROM_DATE)'
                || ' and (:P900_TO_DATE is null or SOURCE_TIMESTAMP < :P900_TO_DATE + 1)'
                || ' order by SOURCE_TIMESTAMP desc';
        else
            return 'select null as SOURCE_ID, null as SOURCE_USER_ID, null as TK,'
                || ' cast(null as timestamp) as SOURCE_TIMESTAMP, null as DEVICE_NAME'
                || ' from dual where 1 = 0';
        end if;
    end get_punch_monitor_sql;

    function get_unmatched_punch_sql return varchar2 is
    begin
        if source_link_available_sql = 1 then
            return 'select SOURCE_ID, SOURCE_USER_ID, TK, SOURCE_TIMESTAMP, DEVICE_NAME'
                || ' from V_UNMATCHED_PUNCH'
                || ' where AUTH_PKG.can_read_sql(''ReadTransactions'') = 1'
                || ' and (:P901_FROM_DATE is null or SOURCE_TIMESTAMP >= :P901_FROM_DATE)'
                || ' and (:P901_TO_DATE is null or SOURCE_TIMESTAMP < :P901_TO_DATE + 1)'
                || ' order by SOURCE_TIMESTAMP desc';
        else
            return 'select null as SOURCE_ID, null as SOURCE_USER_ID, null as TK,'
                || ' cast(null as timestamp) as SOURCE_TIMESTAMP, null as DEVICE_NAME'
                || ' from dual where 1 = 0';
        end if;
    end get_unmatched_punch_sql;

    function get_source_audit_sql return varchar2 is
        l_local varchar2(4000);
    begin
        l_local := 'select ''LOCAL_TRANSACTION'' as SOURCE_TYPE, count(*) as ROW_COUNT,'
            || ' min(t."DATE") as FIRST_DATE, max(t."DATE") as LAST_DATE, ''AVAILABLE'' as SOURCE_STATUS'
            || ' from "TRANSACTION" t join EMPLOYEE e on e.ID = t.EMPLOYEE_ID'
            || ' where AUTH_PKG.can_read_sql(''ReadTransactions'') = 1'
            || ' and e.LOCATION_ID in (select to_number(column_value) from table(apex_string.split(:APP_USER_LOCATION_IDS, '':'')))'
            || ' and (:P902_FROM_DATE is null or t."DATE" >= :P902_FROM_DATE)'
            || ' and (:P902_TO_DATE is null or t."DATE" < :P902_TO_DATE + 1)';
        if source_link_available_sql = 1 then
            return l_local
                || ' union all'
                || ' select ''UNMATCHED_SOURCE_PUNCH'', count(*), min(SOURCE_TIMESTAMP), max(SOURCE_TIMESTAMP), ''AVAILABLE'''
                || ' from V_UNMATCHED_PUNCH'
                || ' where AUTH_PKG.can_read_sql(''ReadTransactions'') = 1'
                || ' and (:P902_FROM_DATE is null or SOURCE_TIMESTAMP >= :P902_FROM_DATE)'
                || ' and (:P902_TO_DATE is null or SOURCE_TIMESTAMP < :P902_TO_DATE + 1)';
        else
            return l_local
                || ' union all'
                || ' select ''UNMATCHED_SOURCE_PUNCH'', 0, cast(null as date), cast(null as date), ''SOURCE_UNAVAILABLE'''
                || ' from dual where AUTH_PKG.can_read_sql(''ReadTransactions'') = 1';
        end if;
    end get_source_audit_sql;

    function get_device_workload_sql return varchar2 is
    begin
        return 'select d.ID as DEVICE_ID, d.NAME as DEVICE_NAME, d.LOCATION_ID,'
            || ' count(t.ID) as TRANSACTION_COUNT,'
            || ' min(t."DATE") as FIRST_TRANSACTION, max(t."DATE") as LAST_TRANSACTION'
            || ' from DEVICE d'
            || ' left join "TRANSACTION" t on t.DEVICE_ID = d.ID'
            || ' and (:P53_FROM_DATE is null or t."DATE" >= :P53_FROM_DATE)'
            || ' and (:P53_TO_DATE is null or t."DATE" < :P53_TO_DATE + 1)'
            || ' where AUTH_PKG.can_read_sql(''ReadTransactions'') = 1'
            || ' and d.LOCATION_ID in (select to_number(column_value) from table(apex_string.split(:APP_USER_LOCATION_IDS, '':'')))'
            || ' group by d.ID, d.NAME, d.LOCATION_ID'
            || ' order by TRANSACTION_COUNT desc, d.NAME';
    end get_device_workload_sql;
end REPORT_API_PKG;
/
