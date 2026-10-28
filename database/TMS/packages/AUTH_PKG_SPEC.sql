
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."AUTH_PKG" as
    /* Authenticates a TMS credential and establishes the current APEX session user. */
    function authenticate(p_username varchar2, p_password varchar2) return boolean;
    /* Returns TRUE only when the APEX session maps to an enabled APP_USER row. */
    function is_authenticated return boolean;
    /* Returns TRUE when the current session must complete its password reset. */
    function is_password_reset_required return boolean;
    /* Replaces the current credential after verifying the current password. */
    procedure change_password(p_current_password varchar2, p_new_password varchar2);
    /* Issues a one-time password for an enabled TMS user from an administrator session. */
    function issue_temporary_password(p_app_user_id number) return varchar2;
    /* One-time credential handoff record. The temporary password exists only in the
       caller's memory: it is never stored in a table, a log, or an audit payload. */
    type t_temp_credential is record (
        APP_USER_ID number,
        USERNAME varchar2(255),
        TEMPORARY_PASSWORD varchar2(128)
    );
    type t_temp_credential_tab is table of t_temp_credential index by pls_integer;
    /* Counts enabled TMS users that still have no APP_CREDENTIAL row and therefore
       cannot log in. Exposes no credential material. */
    function credential_gap_count return number;
    /* Administrator-invoked provisioning for users that have no credential yet.
       Pass a CSV of APP_USER IDs, or NULL to target every enabled user that is
       currently missing a credential. Every issued credential is forced to reset on
       first login. The returned plaintext is for immediate one-time handoff only. */
    function provision_missing_credentials(p_app_user_ids_csv varchar2 default null)
        return t_temp_credential_tab;
    /* Creates or updates a managed application user and its role/location scope. */
    procedure upsert_user(
        p_app_user_id number, p_username varchar2, p_role_code varchar2,
        p_location_ids_csv varchar2, p_enabled char, p_allow_print char,
        p_limited_timesheet char, p_expected_version number, p_idempotency_key varchar2,
        p_result_id out number, p_status out varchar2, p_message out varchar2
    );
    /* Archives/enables a user or changes the approved access flags. */
    procedure set_user_state(
        p_app_user_id number, p_operation varchar2, p_expected_version number, p_idempotency_key varchar2,
        p_status out varchar2, p_message out varchar2
    );
    /* Removes the current APEX session and all session state. */
    procedure logout;
    /* Returns TRUE when the current user has the supplied application role code. */
    function has_role(p_role_code varchar2) return boolean;
    /* Returns TRUE when the current user can read the supplied feature code. */
    function can_read(p_feature_code varchar2) return boolean;
    /* SQL-visible 1/0 equivalent for report predicates. */
    function can_read_sql(p_feature_code varchar2) return number;
    /* Returns TRUE when the current user can write the supplied feature code. */
    function can_write(p_feature_code varchar2) return boolean;
    /* SQL-visible 1/0 equivalent for DML/process predicates. */
    function can_write_sql(p_feature_code varchar2) return number;
    /* Returns TRUE when the current user is scoped to the location or is privileged. */
    function can_access_location(p_location_id number) return boolean;
    /* SQL-visible 1/0 equivalent for location-scope predicates. */
    function can_access_location_sql(p_location_id number) return number;
    /* Returns TRUE when the work date is after the configured location cut date. */
    function is_month_open(p_work_date date, p_location_id number) return boolean;
    /* Colon-delimited list of LOCATION.ID values the current user may see: every
       location for a privileged user (role 1/2), otherwise their assigned locations.
       Meant to be cached once per page load into an application item and consumed via
       a plain SQL set-membership check, instead of calling can_access_location_sql
       once per row of a report -- see accessible_location_ids_csv for why. */
    function accessible_location_ids_csv return varchar2;
    /* Returns TRUE when the employee is eligible for timesheet printing. */
    function can_print_timesheet(p_employee_id number, p_month date) return boolean;
end AUTH_PKG;
/
