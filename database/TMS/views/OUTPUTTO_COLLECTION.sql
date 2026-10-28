
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "TMS"."OUTPUTTO_COLLECTION" ("ID", "FILENAME", "MIMETYPE", "FILE_CONTENT") AS
  select
  seq_id id,
  c001 filename,
  c002 mimetype,
  blob001 file_content
from
  apex_collections
where
  collection_name = 'OUTPUTTO_COLLECTION';
