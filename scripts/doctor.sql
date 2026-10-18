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
-- Fourth argument: DB_MAJOR_VERSION from .env, or the word none when it is not set.
DEFINE db_major_version = '&4'
@@verify_db_access.sql
DECLARE
  v_declared VARCHAR2(16) := '&&db_major_version';
  v_actual   PLS_INTEGER  := DBMS_DB_VERSION.VERSION;
BEGIN
  IF v_declared = 'none' THEN
    DBMS_OUTPUT.PUT_LINE('Database major version ' || v_actual || '; DB_MAJOR_VERSION is not set in .env.');
  ELSIF v_actual != TO_NUMBER(v_declared) THEN
    RAISE_APPLICATION_ERROR(-20031,
      'DB_MAJOR_VERSION=' || v_declared || ' but the database reports major version ' || v_actual
      || '; fix .env or the connection (26ai reports 23).');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Database major version ' || v_actual || ' matches DB_MAJOR_VERSION.');
  END IF;
END;
/
PROMPT SQLcl connection and database identity checks passed.
PROMPT APEX_DOCTOR_VERIFIED:&&expected_user
EXIT SUCCESS ROLLBACK
