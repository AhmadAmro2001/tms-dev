
  CREATE OR REPLACE EDITIONABLE PROCEDURE "TMS"."AOP_OUTPUTTO_COLLECTION" (
  p_output_blob      in blob,
  p_output_filename  in varchar2,
  p_output_mime_type in varchar2
) is
  v_collection_name varchar2(100) := 'OUTPUTTO_COLLECTION';
begin

  if not apex_collection.collection_exists(v_collection_name)  then
    apex_collection.create_or_truncate_collection( v_collection_name );
  end if;

  APEX_COLLECTION.ADD_MEMBER (
    p_collection_name => v_collection_name,
    p_c001            => p_output_filename,
    p_c002            => p_output_mime_type,
    p_blob001         => p_output_blob
  );

end aop_outputto_collection;
/
