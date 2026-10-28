
  CREATE OR REPLACE EDITIONABLE TRIGGER "TMS"."AOP_DOWNSUBSCR_BIU"
    before insert or update
    on aop_downsubscr
    for each row
begin
    if :new.id is null then
        $IF DBMS_DB_VERSION.VER_LE_11 $THEN
        :new.id := aop_downsubscr_seq.nextval;
        $ELSIF DBMS_DB_VERSION.VER_LE_12 $THEN
        :new.id := aop_downsubscr_seq.nextval;
        $ELSE
        :new.id := aop_downsubscr_seq.nextval;
        -- sometimes people still haven't enabled long names in 19c
        --:new.id := to_number(sys_guid(), 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
        $END
    end if;
    if inserting then
        :new.created := sysdate;
        :new.created_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
    end if;
    :new.updated := sysdate;
    :new.updated_by := nvl(sys_context('APEX$SESSION','APP_USER'),user);
end aop_downsubscr_biu;
/
ALTER TRIGGER "TMS"."AOP_DOWNSUBSCR_BIU" ENABLE;
