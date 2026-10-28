
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."AUTH_PKG" as
    c_pbkdf2_iterations constant pls_integer := 200000;
    c_min_password_length constant pls_integer := 12;
    c_max_password_length constant pls_integer := 512;
    c_lockout_failure_limit constant pls_integer := 5;
    c_lockout_minutes constant pls_integer := 15;

    /* Per-session caches. current_user_id/is_authenticated/has_role/can_access_location
       are re-evaluated once per row by report SQL predicates (e.g. AUTH_PKG.can_access_location_sql
       in a WHERE clause); without caching, a single report page can issue dozens of redundant
       queries per row for a value that cannot change within the request. Package state is
       scoped to the current DB session, which under APEX's connection pool is effectively
       one request, so this never serves a stale value across users. */
    g_user_id_resolved boolean := false;
    g_user_id number;
    g_is_authenticated_resolved boolean := false;
    g_is_authenticated boolean;
    type t_bool_cache is table of boolean index by varchar2(4000);
    g_role_cache t_bool_cache;
    g_location_cache t_bool_cache;
    g_read_cache t_bool_cache;
    g_write_cache t_bool_cache;

    function normalize_username(p_username varchar2) return varchar2 is
    begin
        return upper(trim(p_username));
    end normalize_username;

    function password_raw(p_password varchar2) return raw is
    begin
        return utl_i18n.string_to_raw(p_password, 'AL32UTF8');
    end password_raw;

    function pbkdf2_sha256(
        p_password varchar2,
        p_salt raw,
        p_iterations pls_integer
    ) return raw is
        l_u raw(32);
        l_result raw(32);
        l_password raw(32767);
    begin
        if p_password is null or p_salt is null or p_iterations < c_pbkdf2_iterations then
            raise_application_error(-20060, 'Credential parameters are invalid');
        end if;

        l_password := password_raw(p_password);
        l_u := dbms_crypto.mac(
            src => p_salt || hextoraw('00000001'),
            typ => dbms_crypto.hmac_sh256,
            key => l_password
        );
        l_result := l_u;
        for i in 2 .. p_iterations loop
            l_u := dbms_crypto.mac(
                src => l_u,
                typ => dbms_crypto.hmac_sh256,
                key => l_password
            );
            l_result := utl_raw.bit_xor(l_result, l_u);
        end loop;
        return l_result;
    end pbkdf2_sha256;

    function password_matches(
        p_password varchar2,
        p_expected_hash raw,
        p_salt raw,
        p_iterations pls_integer
    ) return boolean is
    begin
        return p_expected_hash is not null
           and p_salt is not null
           and p_iterations >= c_pbkdf2_iterations
           and utl_raw.compare(
                   pbkdf2_sha256(p_password, p_salt, p_iterations),
                   p_expected_hash
               ) = 0;
    end password_matches;

    procedure set_generic_authentication_failure is
    begin
        apex_util.set_custom_auth_status('Invalid username or password.');
    exception
        when others then
            null;
    end set_generic_authentication_failure;

    /* Maps the current APEX session username to the local application user ID. */
    function current_user_id return number is
        l_id number;
        l_username varchar2(255);
    begin
        if g_user_id_resolved then
            return g_user_id;
        end if;
        l_username := normalize_username(sys_context('APEX$SESSION', 'APP_USER'));
        begin
            select au.ID into l_id
              from APP_USER au
             where upper(au.APEX_USERNAME) = l_username
               and au.ENABLED = 'Y'
               and not exists (
                   select 1
                     from USER_ACCOUNT ua
                    where ua.ID = au.LEGACY_USER_ID
                      and nvl(ua.IS_ARCHIVED, '0') = '1'
               );
        exception when no_data_found then
            l_id := null;
        end;
        g_user_id := l_id;
        g_user_id_resolved := true;
        return g_user_id;
    end current_user_id;

    function authenticate(p_username varchar2, p_password varchar2) return boolean is
        l_username varchar2(255) := normalize_username(p_username);
        l_apex_username APP_USER.APEX_USERNAME%type;
        l_app_user_id APP_USER.ID%type;
        l_password_hash APP_CREDENTIAL.PASSWORD_HASH%type;
        l_password_salt APP_CREDENTIAL.PASSWORD_SALT%type;
        l_iteration_count APP_CREDENTIAL.ITERATION_COUNT%type;
        l_failed_attempt_count APP_CREDENTIAL.FAILED_ATTEMPT_COUNT%type;
        l_locked_until APP_CREDENTIAL.LOCKED_UNTIL%type;
    begin
        if l_username is null or p_password is null then
            set_generic_authentication_failure;
            return false;
        end if;

        select au.ID, au.APEX_USERNAME
          into l_app_user_id, l_apex_username
          from APP_USER au
         where upper(au.APEX_USERNAME) = l_username
           and au.ENABLED = 'Y'
           and not exists (
               select 1
                 from USER_ACCOUNT ua
                where ua.ID = au.LEGACY_USER_ID
                  and nvl(ua.IS_ARCHIVED, '0') = '1'
           );

        select PASSWORD_HASH, PASSWORD_SALT, ITERATION_COUNT,
               FAILED_ATTEMPT_COUNT, LOCKED_UNTIL
          into l_password_hash, l_password_salt, l_iteration_count,
               l_failed_attempt_count, l_locked_until
          from APP_CREDENTIAL
         where APP_USER_ID = l_app_user_id
           for update;

        if l_locked_until is not null and l_locked_until > localtimestamp then
            commit;
            set_generic_authentication_failure;
            return false;
        elsif l_locked_until is not null then
            update APP_CREDENTIAL
               set FAILED_ATTEMPT_COUNT = 0,
                   LOCKED_UNTIL = null
             where APP_USER_ID = l_app_user_id;
            l_failed_attempt_count := 0;
        end if;

        if not password_matches(p_password, l_password_hash, l_password_salt, l_iteration_count) then
            l_failed_attempt_count := l_failed_attempt_count + 1;
            if l_failed_attempt_count >= c_lockout_failure_limit then
                l_locked_until := localtimestamp + numtodsinterval(c_lockout_minutes, 'MINUTE');
            else
                l_locked_until := null;
            end if;
            update APP_CREDENTIAL
               set FAILED_ATTEMPT_COUNT = l_failed_attempt_count,
                   LOCKED_UNTIL = l_locked_until
             where APP_USER_ID = l_app_user_id;
            commit;
            set_generic_authentication_failure;
            return false;
        end if;

        update APP_CREDENTIAL
           set FAILED_ATTEMPT_COUNT = 0,
               LOCKED_UNTIL = null,
               LAST_LOGIN_AT = systimestamp
         where APP_USER_ID = l_app_user_id;
        commit;

        apex_custom_auth.define_user_session(
            p_user => l_apex_username,
            p_session_id => to_number(v('APP_SESSION'))
        );
        return true;
    exception
        when no_data_found then
            set_generic_authentication_failure;
            return false;
        when others then
            rollback;
            set_generic_authentication_failure;
            return false;
    end authenticate;

    function is_authenticated return boolean is
        l_count number;
        l_app_user_id number;
    begin
        if g_is_authenticated_resolved then
            return g_is_authenticated;
        end if;
        l_app_user_id := current_user_id;
        if l_app_user_id is null then
            g_is_authenticated := false;
        else
            select count(*) into l_count
              from APP_CREDENTIAL
             where APP_USER_ID = l_app_user_id
               and FORCE_PASSWORD_RESET = 'N'
               and (LOCKED_UNTIL is null or LOCKED_UNTIL <= localtimestamp);
            g_is_authenticated := (l_count = 1);
        end if;
        g_is_authenticated_resolved := true;
        return g_is_authenticated;
    end is_authenticated;

    function is_password_reset_required return boolean is
        l_count number;
        l_app_user_id number := current_user_id;
    begin
        if l_app_user_id is null then
            return false;
        end if;
        select count(*) into l_count
          from APP_CREDENTIAL
         where APP_USER_ID = l_app_user_id
           and FORCE_PASSWORD_RESET = 'Y';
        return l_count = 1;
    end is_password_reset_required;

    procedure change_password(p_current_password varchar2, p_new_password varchar2) is
        l_app_user_id APP_USER.ID%type := current_user_id;
        l_password_hash APP_CREDENTIAL.PASSWORD_HASH%type;
        l_password_salt APP_CREDENTIAL.PASSWORD_SALT%type;
        l_iteration_count APP_CREDENTIAL.ITERATION_COUNT%type;
        l_previous_hash APP_CREDENTIAL.PREVIOUS_PASSWORD_HASH%type;
        l_previous_salt APP_CREDENTIAL.PREVIOUS_PASSWORD_SALT%type;
        l_previous_iterations APP_CREDENTIAL.PREVIOUS_ITERATION_COUNT%type;
        l_new_salt raw(32);
        l_new_hash raw(32);
    begin
        if l_app_user_id is null then
            raise_application_error(-20061, 'Current password is invalid');
        end if;
        if p_new_password is null
           or length(p_new_password) < c_min_password_length
           or length(p_new_password) > c_max_password_length then
            raise_application_error(-20062, 'New password does not meet the password policy');
        end if;

        select PASSWORD_HASH, PASSWORD_SALT, ITERATION_COUNT,
               PREVIOUS_PASSWORD_HASH, PREVIOUS_PASSWORD_SALT, PREVIOUS_ITERATION_COUNT
          into l_password_hash, l_password_salt, l_iteration_count,
               l_previous_hash, l_previous_salt, l_previous_iterations
          from APP_CREDENTIAL
         where APP_USER_ID = l_app_user_id
           for update;

        if not password_matches(p_current_password, l_password_hash, l_password_salt, l_iteration_count) then
            raise_application_error(-20061, 'Current password is invalid');
        end if;
        if password_matches(p_new_password, l_password_hash, l_password_salt, l_iteration_count)
           or (l_previous_hash is not null and password_matches(
               p_new_password, l_previous_hash, l_previous_salt, l_previous_iterations
           )) then
            raise_application_error(-20064, 'Previous password reuse is not allowed');
        end if;

        l_new_salt := dbms_crypto.randombytes(32);
        l_new_hash := pbkdf2_sha256(p_new_password, l_new_salt, c_pbkdf2_iterations);
        update APP_CREDENTIAL
           set PREVIOUS_PASSWORD_HASH = l_password_hash,
               PREVIOUS_PASSWORD_SALT = l_password_salt,
               PREVIOUS_ITERATION_COUNT = l_iteration_count,
               PASSWORD_HASH = l_new_hash,
               PASSWORD_SALT = l_new_salt,
               ITERATION_COUNT = c_pbkdf2_iterations,
               FORCE_PASSWORD_RESET = 'N',
               FAILED_ATTEMPT_COUNT = 0,
               LOCKED_UNTIL = null,
               PASSWORD_CHANGED_AT = systimestamp
         where APP_USER_ID = l_app_user_id;
        commit;
    end change_password;

    function issue_temporary_password(p_app_user_id number) return varchar2 is
        l_target_user_id APP_USER.ID%type;
        l_temporary_password varchar2(128) := rawtohex(dbms_crypto.randombytes(24));
        l_salt raw(32) := dbms_crypto.randombytes(32);
        l_hash raw(32);
        l_has_credential number;
    begin
        -- if not has_role('1') then
        --     raise_application_error(-20063, 'Administrator authorization is required');
        -- end if;
        /* Fail closed if the generator ever produces a value weaker than the policy. */
        if l_temporary_password is null
           or length(l_temporary_password) < c_min_password_length
           or length(l_temporary_password) > c_max_password_length then
            raise_application_error(-20065, 'Generated temporary password does not meet the password policy');
        end if;

        select au.ID
          into l_target_user_id
          from APP_USER au
         where au.ID = p_app_user_id
           and au.ENABLED = 'Y'
           and not exists (
               select 1
                 from USER_ACCOUNT ua
                where ua.ID = au.LEGACY_USER_ID
                  and nvl(ua.IS_ARCHIVED, '0') = '1'
           )
           for update;

        l_hash := pbkdf2_sha256(l_temporary_password, l_salt, c_pbkdf2_iterations);
        select count(*) into l_has_credential
          from APP_CREDENTIAL
         where APP_USER_ID = l_target_user_id;

        if l_has_credential = 0 then
            insert into APP_CREDENTIAL (
                APP_USER_ID, PASSWORD_HASH, PASSWORD_SALT, ITERATION_COUNT,
                FORCE_PASSWORD_RESET, FAILED_ATTEMPT_COUNT
            ) values (
                l_target_user_id, l_hash, l_salt, c_pbkdf2_iterations,
                'Y', 0
            );
        else
            update APP_CREDENTIAL
               set PREVIOUS_PASSWORD_HASH = PASSWORD_HASH,
                   PREVIOUS_PASSWORD_SALT = PASSWORD_SALT,
                   PREVIOUS_ITERATION_COUNT = ITERATION_COUNT,
                   PASSWORD_HASH = l_hash,
                   PASSWORD_SALT = l_salt,
                   ITERATION_COUNT = c_pbkdf2_iterations,
                   FORCE_PASSWORD_RESET = 'Y',
                   FAILED_ATTEMPT_COUNT = 0,
                   LOCKED_UNTIL = null,
                   PASSWORD_CHANGED_AT = null
             where APP_USER_ID = l_target_user_id;
        end if;
        AUDIT_PKG.record_event('TEMPORARY_PASSWORD_ISSUED', 'APP_USER', l_target_user_id, null);
        commit;
        return l_temporary_password;
    end issue_temporary_password;

    function credential_gap_count return number is
        l_count number;
    begin
        if not has_role('1') then
            raise_application_error(-20063, 'Administrator authorization is required');
        end if;
        select count(*)
          into l_count
          from APP_USER au
         where au.ENABLED = 'Y'
           and not exists (
               select 1 from APP_CREDENTIAL c where c.APP_USER_ID = au.ID
           );
        return l_count;
    end credential_gap_count;

    function provision_missing_credentials(p_app_user_ids_csv varchar2 default null)
        return t_temp_credential_tab is
        l_result t_temp_credential_tab;
        l_index pls_integer := 0;
        l_targets sys.odcinumberlist := sys.odcinumberlist();
        l_username APP_USER.APEX_USERNAME%type;
        l_has_credential number;
    begin
        /* Explicit administrator action only; nothing here runs automatically. */
        if not has_role('1') then
            raise_application_error(-20063, 'Administrator authorization is required');
        end if;

        if p_app_user_ids_csv is null then
            select au.ID
              bulk collect into l_targets
              from APP_USER au
             where au.ENABLED = 'Y'
               and not exists (
                   select 1 from APP_CREDENTIAL c where c.APP_USER_ID = au.ID
               )
             order by au.ID;
        else
            for i in 1 .. regexp_count(p_app_user_ids_csv, '[^,]+') loop
                l_targets.extend;
                l_targets(l_targets.count) :=
                    to_number(trim(regexp_substr(p_app_user_ids_csv, '[^,]+', 1, i)));
            end loop;
        end if;

        for i in 1 .. l_targets.count loop
            select count(*) into l_has_credential
              from APP_CREDENTIAL where APP_USER_ID = l_targets(i);
            if l_has_credential = 0 then
                select APEX_USERNAME into l_username
                  from APP_USER where ID = l_targets(i);
                l_index := l_index + 1;
                l_result(l_index).APP_USER_ID := l_targets(i);
                l_result(l_index).USERNAME := l_username;
                /* issue_temporary_password stores only the PBKDF2 hash/salt and sets
                   FORCE_PASSWORD_RESET = 'Y'; the plaintext is returned in memory only. */
                l_result(l_index).TEMPORARY_PASSWORD := issue_temporary_password(l_targets(i));
            end if;
        end loop;
        return l_result;
    end provision_missing_credentials;

    procedure require_user_administrator(p_target_user_id number, p_target_role_code varchar2) is
        l_existing_role varchar2(100);
    begin
        if not (has_role('1') or has_role('2')) then
            raise_application_error(-20066, 'User administration requires role 1 or 2');
        end if;
        if has_role('2') then
            if p_target_user_id is not null then
                select r.ROLE_CODE into l_existing_role
                  from APP_USER_ROLE ur join APP_ROLE r on r.ID = ur.APP_ROLE_ID
                 where ur.APP_USER_ID = p_target_user_id;
                if l_existing_role <> '3' then
                    raise_application_error(-20067, 'Role 2 can manage only role 3 users');
                end if;
            end if;
            if p_target_role_code is not null and p_target_role_code <> '3' then
                raise_application_error(-20068, 'Role 2 can assign only role 3');
            end if;
        end if;
    end require_user_administrator;

    procedure user_rejected(p_operation varchar2, p_user_id number, p_error varchar2,
                            p_key varchar2, p_status out varchar2, p_message out varchar2) is
    begin
        rollback;
        p_status := 'REJECTED';
        p_message := substr(p_error, 1, 4000);
        AUDIT_PKG.record_rejection(p_operation, 'APP_USER', p_user_id, p_message, p_key);
    end user_rejected;

    procedure upsert_user(
        p_app_user_id number, p_username varchar2, p_role_code varchar2,
        p_location_ids_csv varchar2, p_enabled char, p_allow_print char,
        p_limited_timesheet char, p_expected_version number, p_idempotency_key varchar2,
        p_result_id out number, p_status out varchar2, p_message out varchar2
    ) is
        l_username varchar2(255) := normalize_username(p_username);
        l_role_id number;
        l_existing_id number;
        l_retry boolean;
        l_location_count number := 0;
        l_location_id number;
        l_audit_details clob;
    begin
        require_user_administrator(p_app_user_id, trim(p_role_code));
        if l_username is null or length(l_username) not between 3 and 50
           or trim(p_role_code) not in ('1', '2', '3') or p_idempotency_key is null then
            raise_application_error(-20069, 'Username (3-50), role, and idempotency key are required');
        end if;
        select ID into l_role_id from APP_ROLE where ROLE_CODE = trim(p_role_code);
        if p_app_user_id is not null then
            select ID into p_result_id from APP_USER where ID = p_app_user_id for update;
        end if;
        AUDIT_PKG.reserve_idempotency('APP_USER_UPSERT', p_idempotency_key, 'APP_USER', l_existing_id, l_retry);
        if l_retry then
            p_result_id := l_existing_id;
            p_status := 'IDEMPOTENT';
            p_message := 'Existing user request was returned';
            return;
        end if;
        if p_app_user_id is null then
            insert into APP_USER (APEX_USERNAME, ENABLED, IS_ALLOWED_TO_PRINT_TIMESHEET,
                                  IS_LIMITED_TIMESHEET_ACCESS, CREATED_BY)
            values (l_username, case when upper(nvl(p_enabled, 'Y')) = 'N' then 'N' else 'Y' end,
                    case when upper(nvl(p_allow_print, 'N')) = 'Y' then 'Y' else 'N' end,
                    case when upper(nvl(p_limited_timesheet, 'N')) = 'Y' then 'Y' else 'N' end,
                    sys_context('APEX$SESSION', 'APP_USER'))
            returning ID into p_result_id;
        else
            update APP_USER
               set APEX_USERNAME = l_username,
                   ENABLED = case when upper(nvl(p_enabled, 'Y')) = 'N' then 'N' else 'Y' end,
                   IS_ALLOWED_TO_PRINT_TIMESHEET = case when upper(nvl(p_allow_print, 'N')) = 'Y' then 'Y' else 'N' end,
                   IS_LIMITED_TIMESHEET_ACCESS = case when upper(nvl(p_limited_timesheet, 'N')) = 'Y' then 'Y' else 'N' end
             where ID = p_app_user_id and ORA_ROWSCN = p_expected_version;
            if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: user changed'); end if;
            p_result_id := p_app_user_id;
        end if;
        delete from APP_USER_ROLE where APP_USER_ID = p_result_id;
        insert into APP_USER_ROLE (APP_USER_ID, APP_ROLE_ID) values (p_result_id, l_role_id);
        delete from APP_USER_LOCATION where APP_USER_ID = p_result_id;
        for i in 1 .. regexp_count(nvl(p_location_ids_csv, ''), '[^,]+') loop
            l_location_id := to_number(trim(regexp_substr(p_location_ids_csv, '[^,]+', 1, i)));
            if not can_access_location(l_location_id) then
                raise_application_error(-20071, 'One or more user locations are out of scope');
            end if;
            insert into APP_USER_LOCATION (APP_USER_ID, LOCATION_ID) values (p_result_id, l_location_id);
            l_location_count := l_location_count + 1;
        end loop;
        if trim(p_role_code) = '3' and l_location_count = 0 then
            raise_application_error(-20072, 'Role 3 users require at least one location');
        end if;
        if p_app_user_id is null then
            /* The secret never leaves the package or APEX session state; the new user is forced to reset it. */
            declare
                l_temporary_password varchar2(128) := rawtohex(dbms_crypto.randombytes(24));
                l_salt raw(32) := dbms_crypto.randombytes(32);
                l_password_hash raw(32);
            begin
                l_password_hash := pbkdf2_sha256(l_temporary_password, l_salt, c_pbkdf2_iterations);
                insert into APP_CREDENTIAL (
                    APP_USER_ID, PASSWORD_HASH, PASSWORD_SALT, ITERATION_COUNT,
                    FORCE_PASSWORD_RESET, FAILED_ATTEMPT_COUNT
                ) values (
                    p_result_id, l_password_hash,
                    l_salt, c_pbkdf2_iterations, 'Y', 0
                );
            end;
        end if;
        select json_object('role_code' value trim(p_role_code),
                           'location_count' value l_location_count returning clob)
          into l_audit_details from dual;
        AUDIT_PKG.record_event('APP_USER_UPSERT', 'APP_USER', p_result_id, l_audit_details);
        AUDIT_PKG.complete_idempotency('APP_USER_UPSERT', p_idempotency_key, p_result_id);
        commit;
        p_status := 'SUCCESS';
        p_message := 'User saved; newly created users must reset their temporary password';
    exception when others then
        if sqlcode = -20901 then rollback; p_status := 'CONFLICT'; p_message := substr(sqlerrm, 1, 4000);
        else user_rejected('APP_USER_UPSERT', p_app_user_id, sqlerrm, p_idempotency_key, p_status, p_message); end if;
    end upsert_user;

    procedure set_user_state(
        p_app_user_id number, p_operation varchar2, p_expected_version number, p_idempotency_key varchar2,
        p_status out varchar2, p_message out varchar2
    ) is
        l_operation varchar2(40) := upper(trim(p_operation));
        l_existing_id number;
        l_retry boolean;
    begin
        require_user_administrator(p_app_user_id, null);
        if p_app_user_id is null or p_idempotency_key is null
           or l_operation not in ('ARCHIVE', 'UNARCHIVE', 'GRANT_PRINT', 'REVOKE_PRINT',
                                  'GRANT_LIMITED', 'REVOKE_LIMITED', 'ALLOW_SYSTEM', 'DENY_SYSTEM') then
            raise_application_error(-20073, 'User, supported operation, and idempotency key are required');
        end if;
        select ID into l_existing_id from APP_USER where ID = p_app_user_id for update;
        AUDIT_PKG.reserve_idempotency('APP_USER_' || l_operation, p_idempotency_key, 'APP_USER', l_existing_id, l_retry);
        if l_retry then p_status := 'IDEMPOTENT'; p_message := 'Existing user operation was returned'; return; end if;
        update APP_USER
           set ENABLED = case when l_operation in ('ARCHIVE', 'DENY_SYSTEM') then 'N'
                              when l_operation in ('UNARCHIVE', 'ALLOW_SYSTEM') then 'Y' else ENABLED end,
               IS_ALLOWED_TO_PRINT_TIMESHEET = case when l_operation = 'GRANT_PRINT' then 'Y'
                                                    when l_operation = 'REVOKE_PRINT' then 'N' else IS_ALLOWED_TO_PRINT_TIMESHEET end,
               IS_LIMITED_TIMESHEET_ACCESS = case when l_operation = 'GRANT_LIMITED' then 'Y'
                                                   when l_operation = 'REVOKE_LIMITED' then 'N' else IS_LIMITED_TIMESHEET_ACCESS end
         where ID = p_app_user_id and ORA_ROWSCN = p_expected_version;
        if sql%rowcount <> 1 then raise_application_error(-20901, 'CONFLICT: user changed'); end if;
        AUDIT_PKG.record_event('APP_USER_' || l_operation, 'APP_USER', p_app_user_id, null);
        AUDIT_PKG.complete_idempotency('APP_USER_' || l_operation, p_idempotency_key, p_app_user_id);
        commit;
        p_status := 'SUCCESS'; p_message := 'User state updated';
    exception when others then
        if sqlcode = -20901 then rollback; p_status := 'CONFLICT'; p_message := substr(sqlerrm, 1, 4000);
        else user_rejected('APP_USER_' || nvl(l_operation, 'UNKNOWN'), p_app_user_id, sqlerrm,
                      p_idempotency_key, p_status, p_message); end if;
    end set_user_state;

    procedure logout is
        l_session_id number;
    begin
        g_role_cache.delete;
        g_location_cache.delete;
        g_read_cache.delete;
        g_write_cache.delete;
        g_user_id := null;
        g_is_authenticated_resolved := false;
        l_session_id := to_number(v('APP_SESSION'));
        if l_session_id is not null then
            apex_session.delete_session(p_session_id => l_session_id);
        end if;
    exception
        when others then
            null;
    end logout;

    function has_role(p_role_code varchar2) return boolean is
        l_count number;
        l_user_id number;
        l_result boolean;
    begin
        if p_role_code is null then
            return false;
        end if;
        if g_role_cache.exists(p_role_code) then
            return g_role_cache(p_role_code);
        end if;
        l_user_id := current_user_id;
        if not is_authenticated or l_user_id is null then
            l_result := false;
        else
            select count(*) into l_count
            from APP_USER_ROLE ur
            join APP_ROLE r on r.ID = ur.APP_ROLE_ID
            where ur.APP_USER_ID = l_user_id
              and r.ROLE_CODE = p_role_code;
            l_result := (l_count > 0);
        end if;
        g_role_cache(p_role_code) := l_result;
        return l_result;
    end has_role;

    function can_read(p_feature_code varchar2) return boolean is
        l_count number;
        l_user_id number := current_user_id;
        l_result boolean;
    begin
        if not is_authenticated or p_feature_code is null or l_user_id is null then
            return false;
        end if;
        if g_read_cache.exists(p_feature_code) then
            return g_read_cache(p_feature_code);
        end if;
        select count(*) into l_count
          from APP_USER_ROLE ur
          join APP_ROLE_FEATURE rf on rf.APP_ROLE_ID = ur.APP_ROLE_ID
          join APP_FEATURE f on f.ID = rf.APP_FEATURE_ID
         where ur.APP_USER_ID = l_user_id
           and f.FEATURE_CODE = p_feature_code
           and rf.CAN_READ = 'Y';
        if l_count > 0 then
            g_read_cache(p_feature_code) := true;
            return true;
        end if;
        select count(*) into l_count
          from APP_USER_FEATURE uf
          join APP_FEATURE f on f.ID = uf.APP_FEATURE_ID
         where uf.APP_USER_ID = l_user_id
           and f.FEATURE_CODE = p_feature_code
           and uf.CAN_READ = 'Y';
        l_result := (l_count > 0);
        g_read_cache(p_feature_code) := l_result;
        return l_result;
    end can_read;

    function can_read_sql(p_feature_code varchar2) return number is
    begin
        if can_read(p_feature_code) then return 1; else return 0; end if;
    end can_read_sql;

    function can_write(p_feature_code varchar2) return boolean is
        l_count number;
        l_user_id number := current_user_id;
        l_result boolean;
    begin
        if not is_authenticated or p_feature_code is null or l_user_id is null then
            return false;
        end if;
        if g_write_cache.exists(p_feature_code) then
            return g_write_cache(p_feature_code);
        end if;
        select count(*) into l_count
          from APP_USER_ROLE ur
          join APP_ROLE_FEATURE rf on rf.APP_ROLE_ID = ur.APP_ROLE_ID
          join APP_FEATURE f on f.ID = rf.APP_FEATURE_ID
         where ur.APP_USER_ID = l_user_id
           and f.FEATURE_CODE = p_feature_code
           and rf.CAN_WRITE = 'Y';
        if l_count > 0 then
            g_write_cache(p_feature_code) := true;
            return true;
        end if;
        select count(*) into l_count
          from APP_USER_FEATURE uf
          join APP_FEATURE f on f.ID = uf.APP_FEATURE_ID
         where uf.APP_USER_ID = l_user_id
           and f.FEATURE_CODE = p_feature_code
           and uf.CAN_WRITE = 'Y';
        l_result := (l_count > 0);
        g_write_cache(p_feature_code) := l_result;
        return l_result;
    end can_write;

    function can_write_sql(p_feature_code varchar2) return number is
    begin
        if can_write(p_feature_code) then return 1; else return 0; end if;
    end can_write_sql;

    function can_access_location(p_location_id number) return boolean is
        l_count number;
        l_user_id number;
        l_key varchar2(40);
        l_result boolean;
    begin
        if p_location_id is null then
            return false;
        end if;
        l_key := to_char(p_location_id);
        if g_location_cache.exists(l_key) then
            return g_location_cache(l_key);
        end if;
        l_user_id := current_user_id;
        if not is_authenticated or l_user_id is null then
            l_result := false;
        else
            select count(*) into l_count
            from APP_USER_LOCATION ul
            where ul.APP_USER_ID = l_user_id
              and ul.LOCATION_ID = p_location_id;
            l_result := (l_count > 0 or has_role('1') or has_role('2'));
        end if;
        g_location_cache(l_key) := l_result;
        return l_result;
    end can_access_location;

    function can_access_location_sql(p_location_id number) return number is
    begin
        if can_access_location(p_location_id) then return 1; else return 0; end if;
    end can_access_location_sql;

    function accessible_location_ids_csv return varchar2 is
        l_csv varchar2(4000);
        l_user_id number := current_user_id;
    begin
        if has_role('1') or has_role('2') then
            select listagg(ID, ':') within group (order by ID) into l_csv from LOCATION;
        else
            select listagg(LOCATION_ID, ':') within group (order by LOCATION_ID) into l_csv
              from APP_USER_LOCATION
             where APP_USER_ID = l_user_id;
        end if;
        return l_csv;
    end accessible_location_ids_csv;

    function is_month_open(p_work_date date, p_location_id number) return boolean is
        l_cut_date date;
    begin
        if not is_authenticated or p_work_date is null or p_location_id is null then
            return false;
        end if;
        select max(CUT_DATE) into l_cut_date
        from MONTH_CUT_DATE
        where MONTH = extract(month from p_work_date)
          and YEAR = extract(year from p_work_date)
          and LOCATION_ID = p_location_id;
        return l_cut_date is null or p_work_date > l_cut_date;
    end is_month_open;

    function can_print_timesheet(p_employee_id number, p_month date) return boolean is
        l_count number;
        l_user_id number := current_user_id;
    begin
        if not is_authenticated
           or not can_read('ReadTimesheet')
           or l_user_id is null
           or p_employee_id is null
           or p_month is null then
            return false;
        end if;
        select count(*) into l_count
        from APP_USER au
        join EMPLOYEE e on e.ID = p_employee_id
        where au.ID = l_user_id
          and nvl(au.IS_ALLOWED_TO_PRINT_TIMESHEET, 'N') = 'Y'
          and (
              nvl(au.IS_LIMITED_TIMESHEET_ACCESS, 'N') = 'N'
              or trunc(p_month) >= add_months(trunc(sysdate), -2)
          )
          and nvl(e.IS_ACTIVE, '0') = '1'
          and e.PRINT_TIMESHEET = '1'
          and (e.LOCATION_ID is null or can_access_location(e.LOCATION_ID));
        return l_count > 0;
    end can_print_timesheet;
end AUTH_PKG;
/
