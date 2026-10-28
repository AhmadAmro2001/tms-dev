
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "TMS"."V_SOURCE_PUNCH_RECENT" ("SOURCE_ID", "SOURCE_USER_ID", "TK", "SOURCE_TIMESTAMP", "DEVICE_NAME") AS
  select "id" as SOURCE_ID,
     to_char("user_id") as SOURCE_USER_ID,
     "tk" as TK,
     from_tz(cast("devdt" as timestamp), 'UTC') as SOURCE_TIMESTAMP,
     "devnm" as DEVICE_NAME
from punchlog_last30days@BIOSTAR_SQLSERVER_LINK;
