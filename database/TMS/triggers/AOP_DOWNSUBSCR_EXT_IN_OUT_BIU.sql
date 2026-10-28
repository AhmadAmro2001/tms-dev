
  CREATE OR REPLACE EDITIONABLE TRIGGER "TMS"."AOP_DOWNSUBSCR_EXT_IN_OUT_BIU"
    before insert or update
    on aop_downsubscr_ext_in_out
    for each row
begin
    if :new.id is null then
        :new.id := to_number(sys_guid(), 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
    end if;
    if inserting then
        :new.created := sysdate;
        :new.created_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
    end if;
    :new.updated := sysdate;
    :new.updated_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
end aop_downsubscr_ext_in_out_biu;
/
ALTER TRIGGER "TMS"."AOP_DOWNSUBSCR_EXT_IN_OUT_BIU" ENABLE;
