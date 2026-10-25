-- Read-only connection and database identity check used by team doctor.
SET DEFINE ON
SET VERIFY OFF
SET ECHO OFF
-- Only the identity line is wanted: no column heading (SQLcl prints it in ANSI
-- bold when output is redirected) and no "PL/SQL procedure successfully completed".
SET HEADING OFF
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
WHENEVER OSERROR EXIT FAILURE ROLLBACK
DEFINE target_schema = '&1'
DEFINE db_environment = '&2'
DEFINE expected_user = '&3'
@@verify_db_access.sql
@@doctor_database_info.sql
-- SQL*Plus includes cannot be conditional. Select a report or a comment-only
-- script so owner logins keep the existing doctor output unchanged.
COLUMN doctor_session_privilege_script NEW_VALUE doctor_session_privilege_script NOPRINT
SELECT CASE
         WHEN UPPER('&&expected_user') <> UPPER('&&target_schema')
           THEN 'doctor_session_privileges.sql'
         ELSE 'doctor_no_report.sql'
       END AS doctor_session_privilege_script
FROM dual;
@@&&doctor_session_privilege_script
PROMPT SQLcl connection and database identity checks passed.
PROMPT APEX_DOCTOR_VERIFIED:&&expected_user
EXIT SUCCESS ROLLBACK
