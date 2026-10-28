
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "TMS"."V_EMPLOYEE_TRANSACTION_SUMMARY" ("EMPLOYEE_ID", "EMPLOYEE_NUMBER", "EMPLOYEE_NAME", "LOCATION_ID", "WORK_DATE", "FIRST_IN", "LAST_OUT", "TRANSACTION_COUNT") AS
  select e.ID as EMPLOYEE_ID,
       e.EMPLOYEE_NUMBER,
       e.NAME as EMPLOYEE_NAME,
       e.LOCATION_ID,
       trunc(t."DATE") as WORK_DATE,
       min(case when t.TYPE = '0' then t."DATE" end) as FIRST_IN,
       max(case when t.TYPE = '1' then t."DATE" end) as LAST_OUT,
       count(t.ID) as TRANSACTION_COUNT
from EMPLOYEE e
left join "TRANSACTION" t on t.EMPLOYEE_ID = e.ID
where AUTH_PKG.can_access_location_sql(e.LOCATION_ID) = 1
group by e.ID, e.EMPLOYEE_NUMBER, e.NAME, e.LOCATION_ID, trunc(t."DATE");
