
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."APP_CONFIG_PKG" as
    function get_setting(
        p_setting_code varchar2,
        p_as_of_date date default trunc(sysdate)
    ) return varchar2 is
        l_value varchar2(4000);
        l_date date := nvl(p_as_of_date, trunc(sysdate));
    begin
        select SETTING_VALUE into l_value
          from APP_SETTING
         where SETTING_CODE = upper(trim(p_setting_code))
           and IS_ACTIVE = 'Y'
           and l_date between EFFECTIVE_START_DATE and EFFECTIVE_END_DATE
         fetch first 1 rows only;
        return l_value;
    exception when no_data_found then
        return null;
    end get_setting;

    function get_setting_number(
        p_setting_code varchar2,
        p_as_of_date date default trunc(sysdate)
    ) return number is
        l_val varchar2(4000) := get_setting(p_setting_code, p_as_of_date);
    begin
        if l_val is null then
            return null;
        end if;
        return to_number(l_val);
    exception when others then
        return null;
    end get_setting_number;

    procedure set_setting(
        p_setting_code varchar2,
        p_setting_value varchar2,
        p_effective_start_date date default trunc(sysdate),
        p_setting_name varchar2 default null,
        p_data_type varchar2 default 'STRING',
        p_description varchar2 default null
    ) is
        l_code varchar2(100) := upper(trim(p_setting_code));
        l_start date := trunc(nvl(p_effective_start_date, sysdate));
        l_name varchar2(255) := trim(p_setting_name);
        l_type varchar2(30) := upper(trim(nvl(p_data_type, 'STRING')));
        l_desc varchar2(4000) := trim(p_description);
        l_user varchar2(100) := nvl(sys_context('APEX$SESSION', 'APP_USER'), user);
    begin
        if l_code is null then
            raise_application_error(-20080, 'Setting code is required');
        end if;
        update APP_SETTING
           set EFFECTIVE_END_DATE = l_start - 1,
               LAST_UPDATED_BY = l_user,
               LAST_UPDATE_DATE = systimestamp
         where SETTING_CODE = l_code
           and IS_ACTIVE = 'Y'
           and l_start between EFFECTIVE_START_DATE and EFFECTIVE_END_DATE
           and EFFECTIVE_START_DATE < l_start;
        update APP_SETTING
           set SETTING_VALUE = p_setting_value,
               SETTING_NAME = nvl(l_name, SETTING_NAME),
               DATA_TYPE = l_type,
               DESCRIPTION = nvl(l_desc, DESCRIPTION),
               LAST_UPDATED_BY = l_user,
               LAST_UPDATE_DATE = systimestamp
         where SETTING_CODE = l_code
           and IS_ACTIVE = 'Y'
           and EFFECTIVE_START_DATE = l_start;
        if sql%rowcount = 0 then
            insert into APP_SETTING (
                SETTING_CODE, SETTING_NAME, SETTING_VALUE, DATA_TYPE, DESCRIPTION,
                EFFECTIVE_START_DATE, EFFECTIVE_END_DATE, IS_ACTIVE,
                CREATED_BY, CREATION_DATE
            ) values (
                l_code, nvl(l_name, l_code), p_setting_value, l_type, l_desc,
                l_start, to_date('9999-12-31', 'YYYY-MM-DD'), 'Y',
                l_user, systimestamp
            );
        end if;
        commit;
    end set_setting;

    procedure get_version_status(p_app_version varchar2, p_result out clob) is
        l_latest varchar2(4000);
    begin
        l_latest := get_setting('LATEST_APP_VERSION');
        select json_object('app_version' value p_app_version, 'latest_version' value l_latest returning clob)
        into p_result from dual;
    end get_version_status;

    function get_timezone_offset(
        p_date date default trunc(sysdate)
    ) return varchar2 is
        l_offset varchar2(10);
    begin
        l_offset := get_setting('EGYPT_TIMEZONE', p_date);
        return nvl(l_offset, '+02:00');
    end get_timezone_offset;

    function to_local_timestamp(
        p_ts timestamp with time zone
    ) return timestamp with time zone is
        l_utc_ts   timestamp;
        l_offset   varchar2(10);
    begin
        if p_ts is null then
            return null;
        end if;
        l_utc_ts := sys_extract_utc(p_ts);
        l_offset := get_timezone_offset(cast(l_utc_ts as date));
        -- Convert: label as UTC first, then AT TIME ZONE to shift to local
        return from_tz(l_utc_ts, 'UTC') at time zone l_offset;
    end to_local_timestamp;

    function to_local_date(
        p_ts timestamp with time zone
    ) return date is
    begin
        if p_ts is null then
            return null;
        end if;
        return cast(to_local_timestamp(p_ts) as date);
    end to_local_date;
end APP_CONFIG_PKG;
/
