
  CREATE OR REPLACE EDITIONABLE TRIGGER "TMS"."AOP_CONFIG_BIU"
    before insert or update
    on aop_config
    for each row
begin
    if :new.id is null then
        :new.id := 1;
    end if;
    if inserting then
        :new.created := sysdate;
        :new.created_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
    end if;
    :new.updated := sysdate;
    :new.updated_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
end aop_config_biu;
/
ALTER TRIGGER "TMS"."AOP_CONFIG_BIU" ENABLE;
