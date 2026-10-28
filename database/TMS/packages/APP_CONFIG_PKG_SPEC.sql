
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."APP_CONFIG_PKG" as
    /* Returns the requested application version and configured latest version. */
    procedure get_version_status(p_app_version varchar2, p_result out clob);

    /* Returns the setting value effective on the requested date (defaults to today). */
    function get_setting(
        p_setting_code varchar2,
        p_as_of_date date default trunc(sysdate)
    ) return varchar2;

    /* Returns the setting value converted to number, or null if unset/invalid. */
    function get_setting_number(
        p_setting_code varchar2,
        p_as_of_date date default trunc(sysdate)
    ) return number;

    /* Sets or updates a date-tracked configuration parameter, closing prior ranges. */
    procedure set_setting(
        p_setting_code varchar2,
        p_setting_value varchar2,
        p_effective_start_date date default trunc(sysdate),
        p_setting_name varchar2 default null,
        p_data_type varchar2 default 'STRING',
        p_description varchar2 default null
    );

    /* Returns the effective Egypt timezone offset ('+02:00' or '+03:00') for a date. */
    function get_timezone_offset(
        p_date date default trunc(sysdate)
    ) return varchar2;

    /* Converts a UTC TIMESTAMP WITH TIME ZONE to Egypt local TIMESTAMP WITH TIME ZONE. */
    function to_local_timestamp(
        p_ts timestamp with time zone
    ) return timestamp with time zone;

    /* Converts a UTC TIMESTAMP WITH TIME ZONE to Egypt local calendar DATE. */
    function to_local_date(
        p_ts timestamp with time zone
    ) return date;
end APP_CONFIG_PKG;
/
