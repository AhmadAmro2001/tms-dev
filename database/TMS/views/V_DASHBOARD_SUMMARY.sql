
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "TMS"."V_DASHBOARD_SUMMARY" ("ACTIVE_EMPLOYEES", "DEVICES", "TRANSACTIONS", "UNMATCHED_PUNCHES") AS
  select (select count(*) from EMPLOYEE
         where IS_ACTIVE = '1' and AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1) as ACTIVE_EMPLOYEES,
       (select count(*) from DEVICE
         where AUTH_PKG.can_access_location_sql(LOCATION_ID) = 1) as DEVICES,
       (select count(*) from "TRANSACTION" t
         join EMPLOYEE e on e.ID = t.EMPLOYEE_ID
        where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1) as TRANSACTIONS,
       (select case when AUTH_PKG.can_read_sql('ReadTransactions') = 1
                    then count(*) else 0 end from V_UNMATCHED_PUNCH) as UNMATCHED_PUNCHES
from dual;
