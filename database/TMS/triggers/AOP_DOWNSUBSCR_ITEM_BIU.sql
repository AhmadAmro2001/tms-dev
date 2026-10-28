
  CREATE OR REPLACE EDITIONABLE TRIGGER "TMS"."AOP_DOWNSUBSCR_ITEM_BIU"
    before insert or update
    on aop_downsubscr_item
    for each row
begin
    if :new.id is null then
        :new.id := aop_downsubscr_item_seq.nextval;
    end if;
    if inserting then
        :new.created := sysdate;
        :new.created_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
    end if;
    :new.updated := sysdate;
    :new.updated_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
end aop_downsubscr_item_biu;
/
ALTER TRIGGER "TMS"."AOP_DOWNSUBSCR_ITEM_BIU" ENABLE;
