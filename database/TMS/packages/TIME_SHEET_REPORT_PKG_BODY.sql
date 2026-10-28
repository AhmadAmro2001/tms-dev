
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."TIME_SHEET_REPORT_PKG" AS

    PROCEDURE GET_TIME_SHEET_REPORT (
        P_EMPLOYEE_ID IN  EMPLOYEE.ID%TYPE,
        P_YEAR        IN  VARCHAR2,
        P_MONTH       IN  VARCHAR2,
        P_RESULT      OUT SYS_REFCURSOR
    )
    IS
        V_START_DATE DATE;
    BEGIN

        /* 1. Validate the required parameters */

        IF P_EMPLOYEE_ID IS NULL
           OR P_YEAR IS NULL
           OR P_MONTH IS NULL
           OR NOT REGEXP_LIKE(P_YEAR, '^[0-9]{4}$')
           OR NOT REGEXP_LIKE(P_MONTH, '^(0?[1-9]|1[0-2])$')
        THEN
            OPEN P_RESULT FOR
                SELECT *
                FROM EMPLOYEE
                WHERE 1 = 0;

            RETURN;
        END IF;


        /* 2. Convert the selected year and month to a date */

        V_START_DATE := TO_DATE(
            P_YEAR || '-' || LPAD(P_MONTH, 2, '0') || '-01','FXYYYY-MM-DD'
        );


        /* 3. Execute the attendance report query */

        OPEN P_RESULT FOR

            WITH month_dates AS (
                SELECT
                    V_START_DATE + LEVEL - 1 AS TRANSACTION_DATE
                FROM DUAL
                CONNECT BY LEVEL <=
                    LAST_DAY(V_START_DATE) - V_START_DATE + 1
            ),

            transactions_per_day AS (
                SELECT *
                FROM (
                    SELECT
                        T.ID,
                        T.EMPLOYEE_ID,
                        CAST(loc.LT AS TIMESTAMP) AS "DATE",
                        T.TYPE,

                        ROW_NUMBER() OVER (
                            PARTITION BY
                                T.EMPLOYEE_ID,
                                TRUNC(CAST(loc.LT AS DATE)),
                                T.TYPE
                            ORDER BY
                                CASE
                                    WHEN T.TYPE = 0 THEN CAST(loc.LT AS TIMESTAMP)
                                END ASC,

                                CASE
                                    WHEN T.TYPE = 1 THEN CAST(loc.LT AS TIMESTAMP)
                                END DESC
                        ) AS RN

                    FROM TRANSACTION T
                    CROSS APPLY (
                        SELECT APP_CONFIG_PKG.TO_LOCAL_TIMESTAMP(T."DATE") AS LT FROM DUAL
                    ) loc

                    WHERE T.EMPLOYEE_ID = P_EMPLOYEE_ID
                      AND T."DATE" >= FROM_TZ(CAST(V_START_DATE - 1 AS TIMESTAMP), 'UTC')
                      AND T."DATE" < FROM_TZ(CAST(ADD_MONTHS(V_START_DATE, 1) + 2 AS TIMESTAMP), 'UTC')
                )
                WHERE RN = 1
                  AND "DATE" >= CAST(V_START_DATE AS TIMESTAMP)
                  AND "DATE" < CAST(ADD_MONTHS(V_START_DATE, 1) + 1 AS TIMESTAMP)
            ),

            daily_transactions AS (
                SELECT
                    EMPLOYEE_ID,
                    TRUNC("DATE") AS TRANSACTION_DATE,

                    MAX(
                        CASE
                            WHEN TYPE = 0 THEN "DATE"
                        END
                    ) AS IN_TIME,

                    MAX(
                        CASE
                            WHEN TYPE = 1 THEN "DATE"
                        END
                    ) AS OUT_TIME

                FROM transactions_per_day

                GROUP BY
                    EMPLOYEE_ID,
                    TRUNC("DATE")
            ),

            rotation_per_day AS (
                SELECT
                    MD.TRANSACTION_DATE,
                    RH.ROTATION_ID,

                    ROW_NUMBER() OVER (
                        PARTITION BY MD.TRANSACTION_DATE
                        ORDER BY RH.STARTED DESC
                    ) AS RN

                FROM month_dates MD

                JOIN ROTATION_HISTORY RH
                    ON RH.EMPLOYEE_ID = P_EMPLOYEE_ID
                   AND RH.STARTED <= MD.TRANSACTION_DATE
            ),

            rotation_calculation AS (
                SELECT
                    R.TRANSACTION_DATE,
                    R.ROTATION_ID,
                    RP.START_DATE AS ROTATION_START_DATE,
                    RP.DAYS AS ROTATION_DAYS,

                    MOD(
                        TRUNC(R.TRANSACTION_DATE) -
                        TRUNC(RP.START_DATE),
                        RP.DAYS
                    ) + 1 AS ROTATION_DAY

                FROM rotation_per_day R

                JOIN ROTATION_PLAN RP
                    ON RP.ID = R.ROTATION_ID

                WHERE R.RN = 1
            ),
            rotation_shift AS (
                SELECT
                    RD.ROTATION_ID,
                    RD.SHIFT_ID,
                    ROW_NUMBER() OVER (
                        PARTITION BY RD.ROTATION_ID
                        ORDER BY RD.ID
                    ) AS ROTATION_DAY
                FROM ROTATION_DAY RD
            )

            /* Continue with your original final SELECT here */

            SELECT
                E.ID,
                E.EMPLOYEE_NUMBER,
                DT.TRANSACTION_DATE AS ACTUAL_TRANSACTION_DATE,
                MD.TRANSACTION_DATE,
                E.NAME,
                E.PROJECT_ID,
                E.LOCATION_ID,
                E.DEPARTMENT_ID,
                E.IS_ACTIVE,
                E.GRADE_ID,
                E.LAST_TIMESHEET_PRINT_DATE,
                E.NATIONALITY,
                E.RELIGION,
                E.PRINT_TIMESHEET,
                E.CREATED_BY,
                E.CREATION_DATE,
                E.LAST_UPDATED_BY,
                E.LAST_UPDATE_DATE,

                P.ID AS PERMISSION_ID,
                P.TYPE_ID AS PERMISSION_TYPE_ID,
                P.DESCRIPTION AS PERMISSION_DESCRIPTION,
                P.FROM_TIME AS PERMISSION_FROM_TIME,
                P.TO_TIME AS PERMISSION_TO_TIME,

                RC.ROTATION_ID,
                RC.ROTATION_START_DATE,
                RC.ROTATION_DAYS,
                RC.ROTATION_DAY,
                RS.SHIFT_ID,

                TO_CHAR(DT.IN_TIME, 'HH24:MI') AS IN_TIME,
                TO_CHAR(DT.OUT_TIME, 'HH24:MI') AS OUT_TIME,

                CASE
                    when DT.IN_TIME IS NULL AND DT.OUT_TIME IS NULL then null

                     WHEN DT.IN_TIME IS NOT NULL
                         AND DT.OUT_TIME IS NOT NULL
                        AND (DT.OUT_TIME - DT.IN_TIME) >= INTERVAL '7' HOUR
                         AND (DT.OUT_TIME - DT.IN_TIME) <  INTERVAL '8' HOUR
                        THEN '08:00'
                    else
--                    TO_CHAR(
--                        TRUNC(SYSDATE) +
--                        (DT.OUT_TIME - DT.IN_TIME),
--                        'HH24:MI:SS'
--                    )
                         LPAD(
            EXTRACT(DAY FROM (DT.OUT_TIME - DT.IN_TIME)) * 24
            + EXTRACT(HOUR FROM (DT.OUT_TIME - DT.IN_TIME)),
            2,
            '0'
        )
        || ':' ||
        LPAD(
            EXTRACT(MINUTE FROM (DT.OUT_TIME - DT.IN_TIME)),
            2,
            '0'
        )
                END AS WORKED_HOURS,


              CASE
    WHEN DT.OUT_TIME IS NOT NULL
     AND DT.OUT_TIME > TRUNC(DT.OUT_TIME) + (15 * 60 + 44) / 1440
    THEN
        TO_CHAR(
            TRUNC(SYSDATE)
            +
            (
                -- Early arrival overtime
                CASE
                    WHEN DT.IN_TIME IS NOT NULL
                     AND DT.IN_TIME < TRUNC(DT.IN_TIME) + (7 * 60 + 30) / 1440
                    THEN
                        (TRUNC(DT.IN_TIME) + (7 * 60 + 30) / 1440)
                        - DT.IN_TIME
                    else
                        INTERVAL '0' SECOND
                END

                +

                -- Afternoon overtime, capped at 6 PM
                (
                    LEAST(
                        DT.OUT_TIME,
                        TRUNC(DT.OUT_TIME) + 18 / 24
                    )
                    -
                    (
                        TRUNC(DT.OUT_TIME)
                        + (15 * 60 + 15) / 1440
                    )
                )
            ),
            'HH24:MI'
        )
END AS OVER_TIME_BEFORE_6,

        CASE
            WHEN DT.OUT_TIME IS NOT NULL
             AND DT.OUT_TIME > TRUNC(DT.OUT_TIME) + 18 / 24
            THEN
                TO_CHAR(
                    TRUNC(SYSDATE)
                    + (
                        DT.OUT_TIME
                        - (TRUNC(DT.OUT_TIME) + 18 / 24)
                    ),
                    'HH24:MI'
                )
        END AS OVER_TIME_AFTER_6,
--                NULL AS OVER_TIME,

                CASE
                    WHEN V.ID IS NOT NULL THEN 'VACATION'
                    WHEN DT.EMPLOYEE_ID IS NOT NULL THEN 'WORK'
--                    WHEN (UPPER(OFH.TARGET_NATIONALITY) = UPPER('ALL') OR UPPER(E.NATIONALITY) = UPPER(OFH.TARGET_NATIONALITY))
--                    AND (UPPER(E.RELIGION) = UPPER(OFH.TARGET_RELIGION) OR UPPER(OFH.TARGET_RELIGION) = UPPER('ALL'))
--                    THEN 'OFFICIAL HOLIDAY'
                    WHEN OFH.ID IS NOT NULL THEN 'OFFICIAL HOLIDAY'
                    WHEN RS.SHIFT_ID = 4 THEN 'OFF'
                    ELSE 'NO TRANSACTION'
                END AS DAY_STATUS,

                CASE
                    WHEN P.ID IS NOT NULL THEN 'PERMISSION'
                    ELSE 'NO PERMISSION IN THIS DAY'
                END AS PERMISSION_STATUS

            FROM EMPLOYEE E

            CROSS JOIN month_dates MD

            LEFT JOIN daily_transactions DT
                ON DT.EMPLOYEE_ID = E.ID
               AND DT.TRANSACTION_DATE = MD.TRANSACTION_DATE

            LEFT JOIN VACATION V
                ON V.EMPLOYEE_ID = E.ID
               AND MD.TRANSACTION_DATE BETWEEN TRUNC(V.FROM_DATE)
                                           AND TRUNC(V.TO_DATE)

            LEFT JOIN MISSION M
                ON M.EMPLOYEE_ID = E.ID
                AND MD.TRANSACTION_DATE BETWEEN TRUNC(M.FROM_DATE) AND TRUNC(M.TO_DATE)

            LEFT JOIN PERMISSION P
                ON P.EMPLOYEE_ID = E.ID
               AND TRUNC(P."DATE") = MD.TRANSACTION_DATE

            LEFT JOIN OFFICIAL_HOLIDAY OFH
            ON MD.TRANSACTION_DATE BETWEEN TRUNC(OFH.FROM_DATE) AND TRUNC(OFH.TO_DATE)
             AND (
            UPPER(OFH.TARGET_NATIONALITY) = 'ALL'
                OR UPPER(E.NATIONALITY) = UPPER(OFH.TARGET_NATIONALITY)
               )
               AND (
                    UPPER(OFH.TARGET_RELIGION) = 'ALL'
                    OR UPPER(E.RELIGION) = UPPER(OFH.TARGET_RELIGION)
               )

            LEFT JOIN rotation_calculation RC
                ON RC.TRANSACTION_DATE = MD.TRANSACTION_DATE

            LEFT JOIN rotation_shift RS
                ON RS.ROTATION_ID = RC.ROTATION_ID
               AND RS.ROTATION_DAY = RC.ROTATION_DAY

            WHERE E.ID = P_EMPLOYEE_ID

            ORDER BY MD.TRANSACTION_DATE;

    END GET_TIME_SHEET_REPORT;



    FUNCTION GET_TIME_SHEET_REPORT_APEX (
    P_EMPLOYEE_IDS IN VARCHAR2,
    P_YEAR        IN VARCHAR2,
    P_MONTH       IN VARCHAR2,
    P_DEPARTMENT IN VARCHAR2,
    P_LOCATION IN VARCHAR2,
    P_PROJECT IN VARCHAR2
)
RETURN TIME_SHEET_ROW_TABLE
IS
    L_RESULT SYS_REFCURSOR;
    L_ROWS   TIME_SHEET_ROW_TABLE := TIME_SHEET_ROW_TABLE();

    -- Variables for the cursor columns
    L_ID                       NUMBER;
    L_EMPLOYEE_NUMBER          VARCHAR2(100);
    L_ACTUAL_TRANSACTION_DATE  DATE;
    L_TRANSACTION_DATE         DATE;
    L_NAME                     VARCHAR2(500);
    L_PROJECT_ID               EMPLOYEE.PROJECT_ID%TYPE;
    L_PROJECT_NAME             VARCHAR2(500);
    L_LOCATION_ID               EMPLOYEE.LOCATION_ID%TYPE;
    L_LOCATION_NAME            VARCHAR2(500);
    L_DEPARTMENT_ID            NUMBER;
    L_DEPARTMENT_NAME          VARCHAR2(500);
    L_IS_ACTIVE                EMPLOYEE.IS_ACTIVE%TYPE;
    L_GRADE_ID                 NUMBER;
    L_LAST_TIMESHEET_PRINT_DATE DATE;
    L_NATIONALITY              VARCHAR2(200);
    L_RELIGION                 VARCHAR2(200);
    L_PRINT_TIMESHEET          NUMBER;
    L_CREATED_BY               VARCHAR2(200);
    L_CREATION_DATE            TIMESTAMP;
    L_LAST_UPDATED_BY          VARCHAR2(200);
    L_LAST_UPDATE_DATE         TIMESTAMP;
    L_PERMISSION_ID            NUMBER;
    L_PERMISSION_TYPE_ID       NUMBER;
    L_PERMISSION_DESCRIPTION   VARCHAR2(4000);
    L_PERMISSION_FROM_TIME     DATE;
    L_PERMISSION_TO_TIME       DATE;
    L_ROTATION_ID              NUMBER;
    L_ROTATION_START_DATE      DATE;
    L_ROTATION_DAYS            NUMBER;
    L_ROTATION_DAY              NUMBER;
    L_IN_TIME                  VARCHAR2(20);
    L_OUT_TIME                 VARCHAR2(20);
    L_SHIFT_FROM_TIME          VARCHAR2(20);
    L_SHIFT_DURATION           NUMBER;
    L_WORKED_HOURS             VARCHAR2(20);
    L_OVER_TIME_BEFORE_6       VARCHAR2(20);
    L_OVER_TIME_AFTER_6        VARCHAR2(20);
    L_OVERTIME_FROM            VARCHAR2(20);
    L_DAY_STATUS               VARCHAR2(100);
    L_RP                       VARCHAR2(20);
    L_PERMISSION_STATUS        VARCHAR2(100);
    L_SHIFT_ID                NUMBER;

BEGIN

    /* =========================================================
       Call your EXISTING procedure
       ========================================================= */

    GET_TIME_SHEET_REPORT_MULTI(
        P_EMPLOYEE_IDS => P_EMPLOYEE_IDS,
        P_YEAR        => P_YEAR,
        P_MONTH       => P_MONTH,
        P_DEPARTMENT  => P_DEPARTMENT,
        P_LOCATION    => P_LOCATION,
        P_PROJECT      => P_PROJECT,
        P_RESULT      => L_RESULT
    );


    /* =========================================================
       Fetch the SYS_REFCURSOR
       ========================================================= */

    LOOP

        FETCH L_RESULT INTO
            L_ID,
            L_EMPLOYEE_NUMBER,
            L_ACTUAL_TRANSACTION_DATE,
            L_TRANSACTION_DATE,
            L_NAME,
            L_PROJECT_ID,
            L_PROJECT_NAME,
            L_LOCATION_ID,
            L_LOCATION_NAME,
            L_DEPARTMENT_ID,
            L_DEPARTMENT_NAME,
            L_IS_ACTIVE,
            L_GRADE_ID,
            L_LAST_TIMESHEET_PRINT_DATE,
            L_NATIONALITY,
            L_RELIGION,
            L_PRINT_TIMESHEET,
            L_CREATED_BY,
            L_CREATION_DATE,
            L_LAST_UPDATED_BY,
            L_LAST_UPDATE_DATE,
            L_PERMISSION_ID,
            L_PERMISSION_TYPE_ID,
            L_PERMISSION_DESCRIPTION,
            L_PERMISSION_FROM_TIME,
            L_PERMISSION_TO_TIME,
            L_ROTATION_ID,
            L_ROTATION_START_DATE,
            L_ROTATION_DAYS,
            L_ROTATION_DAY,
            L_SHIFT_ID,
            L_IN_TIME,
            L_OUT_TIME,
            L_SHIFT_FROM_TIME,
            L_SHIFT_DURATION,
            L_WORKED_HOURS,
            L_OVER_TIME_BEFORE_6,
            L_OVER_TIME_AFTER_6,
            L_OVERTIME_FROM,
            L_DAY_STATUS,
            L_RP,
            L_PERMISSION_STATUS;


        EXIT WHEN L_RESULT%NOTFOUND;


        /* =====================================================
           Add the row to the collection
           ===================================================== */

        L_ROWS.EXTEND;

        L_ROWS(L_ROWS.COUNT) :=
            TIME_SHEET_ROW(
                L_ID,
                L_EMPLOYEE_NUMBER,
                L_ACTUAL_TRANSACTION_DATE,
                L_TRANSACTION_DATE,
                L_NAME,
                L_PROJECT_ID,
                L_LOCATION_ID,
                L_DEPARTMENT_ID,
                L_IS_ACTIVE,
                L_GRADE_ID,
                L_LAST_TIMESHEET_PRINT_DATE,
                L_NATIONALITY,
                L_RELIGION,
                L_PRINT_TIMESHEET,
                L_CREATED_BY,
                L_CREATION_DATE,
                L_LAST_UPDATED_BY,
                L_LAST_UPDATE_DATE,
                L_PERMISSION_ID,
                L_PERMISSION_TYPE_ID,
                L_PERMISSION_DESCRIPTION,
                L_PERMISSION_FROM_TIME,
                L_PERMISSION_TO_TIME,
                L_ROTATION_ID,
                L_ROTATION_START_DATE,
                L_ROTATION_DAYS,
                L_ROTATION_DAY,
                L_IN_TIME,
                L_OUT_TIME,
                L_WORKED_HOURS,
                L_DAY_STATUS,
                L_PERMISSION_STATUS,
                L_SHIFT_ID,
                L_OVER_TIME_BEFORE_6,
                L_OVER_TIME_AFTER_6,
                L_RP,
                L_PROJECT_NAME,
                L_LOCATION_NAME,
                L_DEPARTMENT_NAME,
                L_SHIFT_FROM_TIME,
                L_SHIFT_DURATION,
                L_OVERTIME_FROM

            );

    END LOOP;


    /* =========================================================
       Close cursor
       ========================================================= */

    CLOSE L_RESULT;


    RETURN L_ROWS;

END GET_TIME_SHEET_REPORT_APEX;


PROCEDURE GET_TIME_SHEET_REPORT_MULTI  (
        P_EMPLOYEE_IDS IN  VARCHAR2,
        P_YEAR        IN  VARCHAR2,
        P_MONTH       IN  VARCHAR2,
        P_DEPARTMENT IN VARCHAR2,
        P_LOCATION IN VARCHAR2,
        P_PROJECT IN VARCHAR2,
        P_RESULT      OUT SYS_REFCURSOR
    )
    IS
        V_START_DATE DATE;
    BEGIN

        /* 1. Validate the required parameters */

        IF P_YEAR IS NULL
           OR P_MONTH IS NULL
--           OR (
--                P_EMPLOYEE_IDS IS NULL
--                AND P_DEPARTMENT IS NULL
--                AND P_LOCATION IS NULL
--                AND P_PROJECT IS NULL
--              )
           OR NOT REGEXP_LIKE(P_YEAR, '^[0-9]{4}$')
           OR NOT REGEXP_LIKE(P_MONTH, '^(0?[1-9]|1[0-2])$')
        THEN
            OPEN P_RESULT FOR
                SELECT *
                FROM EMPLOYEE
                WHERE 1 = 0;

            RETURN;
        END IF;


        /* 2. Convert the selected year and month to a date */

        V_START_DATE := TO_DATE(
            P_YEAR || '-' || LPAD(P_MONTH, 2, '0') || '-01','FXYYYY-MM-DD'
        );


        /* 3. Execute the attendance report query */

        OPEN P_RESULT FOR

            WITH month_dates AS (
                SELECT
                    V_START_DATE + LEVEL - 1 AS TRANSACTION_DATE
                FROM DUAL
                CONNECT BY LEVEL <=
                    LAST_DAY(V_START_DATE) - V_START_DATE + 1
            ),

--            transactions_per_day AS (
--                SELECT *
--                FROM (
--                    SELECT
--                        T.*,
--
--                        ROW_NUMBER() OVER (
--                            PARTITION BY
--                                T.EMPLOYEE_ID,
--                                TRUNC(T."DATE"),
--                                T.TYPE
--                            ORDER BY
--                                CASE
--                                    WHEN T.TYPE = 0 THEN T."DATE"
--                                END ASC,
--
--                                CASE
--                                    WHEN T.TYPE = 1 THEN T."DATE"
--                                END DESC
--                        ) AS RN
--
--                    FROM TRANSACTION T
--
--                    WHERE T.EMPLOYEE_ID IN (
--                        SELECT TO_NUMBER(COLUMN_VALUE)
--                        FROM TABLE(APEX_STRING.SPLIT(P_EMPLOYEE_IDS, ':'))
--                    )
--                      AND T."DATE" >= V_START_DATE
--                      AND T."DATE" < ADD_MONTHS(V_START_DATE, 1)
--                )
--                WHERE RN = 1
--            ),
--
--            daily_transactions AS (
--                SELECT
--                    EMPLOYEE_ID,
--                    TRUNC("DATE") AS TRANSACTION_DATE,
--
--                    MAX(
--                        CASE
--                            WHEN TYPE = 0 THEN "DATE"
--                        END
--                    ) AS IN_TIME,
--
--                    MAX(
--                        CASE
--                            WHEN TYPE = 1 THEN "DATE"
--                        END
--                    ) AS OUT_TIME
--
--                FROM transactions_per_day
--
--                GROUP BY
--                    EMPLOYEE_ID,
--                    TRUNC("DATE")
--            ),

                  transactions_per_day AS (
                SELECT *
                FROM (
                    SELECT
                        T.ID,
                        T.EMPLOYEE_ID,
                        CAST(loc.LT AS TIMESTAMP) AS "DATE",
                        T.TYPE,

                        ROW_NUMBER() OVER (
                            PARTITION BY
                                T.EMPLOYEE_ID,
                                TRUNC(CAST(loc.LT AS DATE)),
                                T.TYPE
                            ORDER BY
                                CASE
                                    WHEN T.TYPE = 0 THEN CAST(loc.LT AS TIMESTAMP)
                                END ASC,

                                CASE
                                    WHEN T.TYPE = 1 THEN CAST(loc.LT AS TIMESTAMP)
                                END DESC
                        ) AS RN

                    FROM TRANSACTION T
                    CROSS APPLY (
                        SELECT APP_CONFIG_PKG.TO_LOCAL_TIMESTAMP(T."DATE") AS LT FROM DUAL
                    ) loc

                    WHERE
            (
                P_EMPLOYEE_IDS IS NULL

                OR

                T.EMPLOYEE_ID IN (
                    SELECT TO_NUMBER(COLUMN_VALUE)
                    FROM TABLE(
                        APEX_STRING.SPLIT(
                            P_EMPLOYEE_IDS,
                            ':'
                        )
                    )
                )
            )

            AND T."DATE" >= FROM_TZ(
                CAST(V_START_DATE - 1 AS TIMESTAMP),
                'UTC'
            )

            AND T."DATE" < FROM_TZ(
                CAST(ADD_MONTHS(V_START_DATE, 1) + 2 AS TIMESTAMP),
                'UTC'
            )
    )

    WHERE RN = 1

      AND "DATE" >= CAST(
            V_START_DATE AS TIMESTAMP
          )

      AND "DATE" < CAST(
            ADD_MONTHS(V_START_DATE, 1) + 1 AS TIMESTAMP
          )
),
            daily_transactions AS (
                SELECT
                    I.EMPLOYEE_ID,

                    TRUNC(I."DATE") AS TRANSACTION_DATE,

                    I."DATE" AS IN_TIME,

                    (
                        SELECT MIN(O."DATE")
                        FROM transactions_per_day O
                        WHERE O.EMPLOYEE_ID = I.EMPLOYEE_ID
                          AND O.TYPE = 1

                          -- OUT transaction must have a greater ID
                          AND O.ID > I.ID

                          -- OUT must be within 24 hours from IN
                          AND O."DATE" <= I."DATE" + 1

                          -- OUT should happen after IN
                          AND O."DATE" > I."DATE"
                    ) AS OUT_TIME

                FROM transactions_per_day I

                WHERE I.TYPE = 0
            ),

            rotation_per_day AS (
                    SELECT
                        RH.EMPLOYEE_ID,
                        MD.TRANSACTION_DATE,
                        RH.ROTATION_ID,

                        ROW_NUMBER() OVER (
                            PARTITION BY
                                RH.EMPLOYEE_ID,
                                MD.TRANSACTION_DATE
                            ORDER BY
                                RH.STARTED DESC
                        ) AS RN

                    FROM month_dates MD

                    JOIN ROTATION_HISTORY RH
                       ON RH.STARTED <= MD.TRANSACTION_DATE
                    JOIN EMPLOYEE E
                        ON E.ID = RH.EMPLOYEE_ID

                     WHERE
            (
                (
                    P_EMPLOYEE_IDS IS NULL
                    AND P_DEPARTMENT IS NULL
                    AND P_LOCATION IS NULL
                    AND P_PROJECT IS NULL
                )
                OR
                   (
                       P_EMPLOYEE_IDS IS NOT NULL
                       AND E.ID IN (
                           SELECT TO_NUMBER(COLUMN_VALUE)
                           FROM TABLE(APEX_STRING.SPLIT(P_EMPLOYEE_IDS, ':'))
                       )
                   )
                OR (
                       P_DEPARTMENT IS NOT NULL
                       AND E.DEPARTMENT_ID = P_DEPARTMENT
                   )
                OR (
                       P_LOCATION IS NOT NULL
                       AND E.LOCATION_ID = P_LOCATION
                   )
                OR (
                       P_PROJECT IS NOT NULL
                       AND E.PROJECT_ID = P_PROJECT
                   )
            )
                ),

            rotation_calculation AS (
                SELECT
                    R.EMPLOYEE_ID,
                    R.TRANSACTION_DATE,
                    R.ROTATION_ID,
                    RP.START_DATE AS ROTATION_START_DATE,
                    RP.DAYS AS ROTATION_DAYS,

                    MOD(
                        TRUNC(R.TRANSACTION_DATE) -
                        TRUNC(RP.START_DATE),
                        RP.DAYS
                    ) + 1 AS ROTATION_DAY

                FROM rotation_per_day R

                JOIN ROTATION_PLAN RP
                    ON RP.ID = R.ROTATION_ID

                WHERE R.RN = 1
            ),
            rotation_shift AS (
                SELECT
                    RD.ROTATION_ID,
                    RD.SHIFT_ID,
                    ROW_NUMBER() OVER (
                        PARTITION BY RD.ROTATION_ID
                        ORDER BY RD.DAY -- ID
                    ) AS ROTATION_DAY
                FROM ROTATION_DAY RD
            )

            /* Continue with your original final SELECT here */

            SELECT
                E.ID,
                E.EMPLOYEE_NUMBER,
                DT.TRANSACTION_DATE AS ACTUAL_TRANSACTION_DATE,
                MD.TRANSACTION_DATE,
                E.NAME,
                E.PROJECT_ID,
                PRO.NAME,
                E.LOCATION_ID,
                LO.NAME,
                E.DEPARTMENT_ID,
                DE.NAME,

                E.IS_ACTIVE,
                E.GRADE_ID,
                E.LAST_TIMESHEET_PRINT_DATE,
                E.NATIONALITY,
                E.RELIGION,
                E.PRINT_TIMESHEET,
                E.CREATED_BY,
                E.CREATION_DATE,
                E.LAST_UPDATED_BY,
                E.LAST_UPDATE_DATE,

                P.ID AS PERMISSION_ID,
                P.TYPE_ID AS PERMISSION_TYPE_ID,
                P.DESCRIPTION AS PERMISSION_DESCRIPTION,
                P.FROM_TIME AS PERMISSION_FROM_TIME,
                P.TO_TIME AS PERMISSION_TO_TIME,

                RC.ROTATION_ID,
                RC.ROTATION_START_DATE,
                RC.ROTATION_DAYS,
                RC.ROTATION_DAY,
                RS.SHIFT_ID,


                TO_CHAR(DT.IN_TIME, 'HH24:MI') AS IN_TIME,
                TO_CHAR(DT.OUT_TIME, 'HH24:MI') AS OUT_TIME,
                TO_CHAR(S.FROM_DATE, 'HH24:MI') AS SHIFT_FROM_TIME,
                S.DURATION AS SHIFT_DURATION,



CASE
    WHEN DT.IN_TIME IS NULL
      OR DT.OUT_TIME IS NULL
      OR S.DURATION IS NULL
    THEN NULL

    ELSE
        TO_CHAR(
            FLOOR(
                LEAST(
                    CASE
                        WHEN (
                            LEAST(
                                ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                + CASE
                                    WHEN ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                       < ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                    THEN 1440
                                    ELSE 0
                                  END,
                                ROUND((CAST(S.FROM_DATE AS DATE) - TRUNC(CAST(S.FROM_DATE AS DATE))) * 1440 / 30) * 30 + (S.DURATION * 60)
                            )
                            -
                            CASE
                                WHEN E.LOCATION_ID = 1
                                 AND (CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 BETWEEN 450 AND 494
                                THEN 450
                                ELSE ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                            END
                        ) > 420
                        AND (
                            LEAST(
                                ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                + CASE
                                    WHEN ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                       < ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                    THEN 1440
                                    ELSE 0
                                  END,
                                ROUND((CAST(S.FROM_DATE AS DATE) - TRUNC(CAST(S.FROM_DATE AS DATE))) * 1440 / 30) * 30 + (S.DURATION * 60)
                            )
                            -
                            CASE
                                WHEN E.LOCATION_ID = 1
                                 AND (CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 BETWEEN 450 AND 494
                                THEN 450
                                ELSE ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                            END
                        ) < 480
                        THEN 480

                        ELSE
                            LEAST(
                                ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                + CASE
                                    WHEN ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                       < ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                    THEN 1440
                                    ELSE 0
                                  END,
                                ROUND((CAST(S.FROM_DATE AS DATE) - TRUNC(CAST(S.FROM_DATE AS DATE))) * 1440 / 30) * 30 + (S.DURATION * 60)
                            )
                            -
                            CASE
                                WHEN E.LOCATION_ID = 1
                                 AND (CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 BETWEEN 450 AND 494
                                THEN 450
                                ELSE ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                            END
                    END,
                    S.DURATION * 60
                ) / 60
            ),
            'FM00'
        )
        || ':' ||
        LPAD(
            TO_CHAR(
                MOD(
                    LEAST(
                        CASE
                            WHEN (
                                LEAST(
                                    ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                    + CASE
                                        WHEN ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                           < ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                        THEN 1440
                                        ELSE 0
                                      END,
                                    ROUND((CAST(S.FROM_DATE AS DATE) - TRUNC(CAST(S.FROM_DATE AS DATE))) * 1440 / 30) * 30 + (S.DURATION * 60)
                                )
                                -
                                CASE
                                    WHEN E.LOCATION_ID = 1
                                     AND (CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 BETWEEN 450 AND 494
                                    THEN 450
                                    ELSE ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                END
                            ) > 420
                            AND (
                                LEAST(
                                    ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                    + CASE
                                        WHEN ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                           < ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                        THEN 1440
                                        ELSE 0
                                      END,
                                    ROUND((CAST(S.FROM_DATE AS DATE) - TRUNC(CAST(S.FROM_DATE AS DATE))) * 1440 / 30) * 30 + (S.DURATION * 60)
                                )
                                -
                                CASE
                                    WHEN E.LOCATION_ID = 1
                                     AND (CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 BETWEEN 450 AND 494
                                    THEN 450
                                    ELSE ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                END
                            ) < 480
                            THEN 480
                            ELSE
                                LEAST(
                                    ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                    + CASE
                                        WHEN ROUND((CAST(DT.OUT_TIME AS DATE) - TRUNC(CAST(DT.OUT_TIME AS DATE))) * 1440 / 30) * 30
                                           < ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                        THEN 1440
                                        ELSE 0
                                      END,
                                    ROUND((CAST(S.FROM_DATE AS DATE) - TRUNC(CAST(S.FROM_DATE AS DATE))) * 1440 / 30) * 30 + (S.DURATION * 60)
                                )
                                -
                                CASE
                                    WHEN E.LOCATION_ID = 1
                                     AND (CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 BETWEEN 450 AND 494
                                    THEN 450
                                    ELSE ROUND((CAST(DT.IN_TIME AS DATE) - TRUNC(CAST(DT.IN_TIME AS DATE))) * 1440 / 30) * 30
                                END
                        END,
                        S.DURATION * 60
                    ),
                    60
                )
            ),
            2,
            '0'
        )
END AS WORKED_HOURS,



--    CASE
--    WHEN DT.OUT_TIME IS NULL
--      OR DT.IN_TIME IS NULL
--      OR S.FROM_DATE IS NULL
--      OR S.DURATION IS NULL
--    THEN NULL
--
--    ELSE
--        TO_CHAR(
--            TRUNC(SYSDATE)
--            +
--            (
--                /* ==========================================
--                   1. EARLY ARRIVAL OVERTIME
--                   From actual IN time until SHIFT_FROM_TIME
--                   But never before 06:00
--                   ========================================== */
--                CASE
--                    WHEN CAST(DT.IN_TIME AS DATE) <
--                         (
--                             TRUNC(CAST(DT.IN_TIME AS DATE))
--                             + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                         )
--                    THEN
--                        GREATEST(
--                            0,
--                            (
--                                TRUNC(CAST(DT.IN_TIME AS DATE))
--                                + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                            )
--                            -
--                            GREATEST(
--                                CAST(DT.IN_TIME AS DATE),
--                                TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
--                            )
--                        )
--                    ELSE
--                        0
--                END
--
--                +
--
--                /* ==========================================
--                   2. LATE DEPARTURE OVERTIME
--                   From SHIFT_END until OUT_TIME
--                   Only the part before 18:00
--                   ========================================== */
--                CASE
--                    WHEN CAST(DT.OUT_TIME AS DATE) >
--                         (
--                             TRUNC(CAST(DT.IN_TIME AS DATE))
--                             + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                             + (S.DURATION / 24)
--                         )
--                    THEN
--                        GREATEST(
--                            0,
--                            LEAST(
--                                CAST(DT.OUT_TIME AS DATE),
--                                TRUNC(CAST(DT.OUT_TIME AS DATE)) + 18 / 24
--                            )
--                            -
--                            GREATEST(
--                                (
--                                    TRUNC(CAST(DT.IN_TIME AS DATE))
--                                    + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                                    + (S.DURATION / 24)
--                                ),
--                                TRUNC(CAST(DT.OUT_TIME AS DATE)) + 6 / 24
--                            )
--                        )
--                    ELSE
--                        0
--                END
--            ),
--            'HH24:MI'
--        )
--END AS OVER_TIME_BEFORE_6,

CASE
    WHEN DT.IN_TIME IS NULL
      OR DT.OUT_TIME IS NULL
      OR S.FROM_DATE IS NULL
      OR S.DURATION IS NULL
    THEN NULL

    ELSE
        TO_CHAR(
            TRUNC(SYSDATE)
            +
            (
                /* ==========================================
                   1. EARLY ARRIVAL OVERTIME
                   Use rounded IN_TIME
                   ========================================== */
                CASE
                    WHEN (
                        TRUNC(CAST(DT.IN_TIME AS DATE))
                        +
                        ROUND(
                            (
                                CAST(DT.IN_TIME AS DATE)
                                - TRUNC(CAST(DT.IN_TIME AS DATE))
                            ) * 1440 / 30
                        ) * 30 / 1440
                    ) <
                    (
                        TRUNC(CAST(DT.IN_TIME AS DATE))
                        + (S.FROM_DATE - TRUNC(S.FROM_DATE))
                    )
                    THEN
                        GREATEST(
                            0,
                            (
                                TRUNC(CAST(DT.IN_TIME AS DATE))
                                + (S.FROM_DATE - TRUNC(S.FROM_DATE))
                            )
                            -
                            GREATEST(
                                TRUNC(CAST(DT.IN_TIME AS DATE))
                                +
                                ROUND(
                                    (
                                        CAST(DT.IN_TIME AS DATE)
                                        - TRUNC(CAST(DT.IN_TIME AS DATE))
                                    ) * 1440 / 30
                                ) * 30 / 1440,
                                TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
                            )
                        )
                    ELSE 0
                END

                +

                /* ==========================================
                   2. LATE DEPARTURE OVERTIME
                   Use rounded OUT_TIME
                   Handle overnight attendance
                   ========================================== */
                CASE
                    WHEN (
                        TRUNC(CAST(DT.OUT_TIME AS DATE))
                        +
                        ROUND(
                            (
                                CAST(DT.OUT_TIME AS DATE)
                                - TRUNC(CAST(DT.OUT_TIME AS DATE))
                            ) * 1440 / 30
                        ) * 30 / 1440
                        +
                        CASE
                            WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
                            ELSE 0
                        END
                    ) >
                    (
                        TRUNC(CAST(DT.IN_TIME AS DATE))
                        + (S.FROM_DATE - TRUNC(S.FROM_DATE))
                        + (S.DURATION / 24)
                    )
                    THEN
                        GREATEST(
                            0,
                            LEAST(
                                (
                                    TRUNC(CAST(DT.OUT_TIME AS DATE))
                                    +
                                    ROUND(
                                        (
                                            CAST(DT.OUT_TIME AS DATE)
                                            - TRUNC(CAST(DT.OUT_TIME AS DATE))
                                        ) * 1440 / 30
                                    ) * 30 / 1440
                                    +
                                    CASE
                                        WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
                                        ELSE 0
                                    END
                                ),
                                TRUNC(
                                    CAST(DT.OUT_TIME AS DATE)
                                    +
                                    CASE
                                        WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
                                        ELSE 0
                                    END
                                ) + 18 / 24
                            )
                            -
                            GREATEST(
                                (
                                    TRUNC(CAST(DT.IN_TIME AS DATE))
                                    + (S.FROM_DATE - TRUNC(S.FROM_DATE))
                                    + (S.DURATION / 24)
                                ),
                                TRUNC(
                                    CAST(DT.OUT_TIME AS DATE)
                                    +
                                    CASE
                                        WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
                                        ELSE 0
                                    END
                                ) + 6 / 24
                            )
                        )
                    ELSE 0
                END
            ),
            'HH24:MI'
        )
END AS OVER_TIME_BEFORE_6,

--        CASE
--    WHEN DT.OUT_TIME IS NULL
--      OR DT.IN_TIME IS NULL
--      OR S.FROM_DATE IS NULL
--      OR S.DURATION IS NULL
--    THEN NULL
--
--    ELSE
--        TO_CHAR(
--            TRUNC(SYSDATE)
--            +
--            (
--                /* =====================================================
--                   CASE 1:
--                   OUT_TIME is after SHIFT_END.
--                   Count only the part after 18:00.
--                   ===================================================== */
--                CASE
--                    WHEN CAST(DT.OUT_TIME AS DATE) >
--                         (
--                             TRUNC(CAST(DT.IN_TIME AS DATE))
--                             + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                             + (S.DURATION / 24)
--                         )
--                    THEN
--                        GREATEST(
--                            0,
--                            CAST(DT.OUT_TIME AS DATE)
--                            -
--                            GREATEST(
--                                (
--                                    TRUNC(CAST(DT.IN_TIME AS DATE))
--                                    + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                                    + (S.DURATION / 24)
--                                ),
--                                TRUNC(CAST(DT.OUT_TIME AS DATE)) + 18 / 24
--                            )
--                        )
--                    ELSE
--                        0
--                END
--
--                +
--
--                /* =====================================================
--                   CASE 2:
--                   IN_TIME is before SHIFT_START
--                   AND IN_TIME is between 18:00 and 06:00.
--
--                   If IN is 00:00 -> 06:00:
--                       IN -> 06:00
--
--                   If IN is 18:00 -> 23:59:
--                       IN -> midnight
--                   ===================================================== */
--                CASE
--                    WHEN CAST(DT.IN_TIME AS DATE) <
--                         (
--                             TRUNC(CAST(DT.IN_TIME AS DATE))
--                             + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                         )
--                     AND
--                     (
--                         CAST(DT.IN_TIME AS DATE) >=
--                             TRUNC(CAST(DT.IN_TIME AS DATE)) + 18 / 24
--
--                         OR
--
--                         CAST(DT.IN_TIME AS DATE) <
--                             TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
--                     )
--                    THEN
--                        CASE
--                            /* 00:00 -> 06:00 */
--                            WHEN CAST(DT.IN_TIME AS DATE) <
--                                 TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
--                            THEN
--                                (
--                                    TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
--                                )
--                                -
--                                CAST(DT.IN_TIME AS DATE)
--
--                            /* 18:00 -> 00:00 */
--                            ELSE
--                                (
--                                    TRUNC(CAST(DT.IN_TIME AS DATE)) + 1
--                                )
--                                -
--                                CAST(DT.IN_TIME AS DATE)
--                        END
--                    ELSE
--                        0
--                END
--            ),
--            'HH24:MI'
--        )
--END AS OVER_TIME_AFTER_6,

CASE
    WHEN DT.OUT_TIME IS NULL
      OR DT.IN_TIME IS NULL
      OR S.FROM_DATE IS NULL
      OR S.DURATION IS NULL
    THEN NULL

    ELSE
        TO_CHAR(
            TRUNC(SYSDATE)
            +
            (
                /* =====================================================
                   CASE 1:
                   OUT_TIME is after SHIFT_END.
                   Count only the part after 18:00.
                   Use rounded OUT_TIME.
                   ===================================================== */
                CASE
                    WHEN (
                        TRUNC(CAST(DT.OUT_TIME AS DATE))
                        +
                        ROUND(
                            (
                                CAST(DT.OUT_TIME AS DATE)
                                - TRUNC(CAST(DT.OUT_TIME AS DATE))
                            ) * 1440 / 30
                        ) * 30 / 1440
                        +
                        CASE
                            WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
                            ELSE 0
                        END
                    ) >
                    (
                        TRUNC(CAST(DT.IN_TIME AS DATE))
                        + (S.FROM_DATE - TRUNC(S.FROM_DATE))
                        + (S.DURATION / 24)
                    )
                    THEN
                        GREATEST(
                            0,
                            (
                                TRUNC(CAST(DT.OUT_TIME AS DATE))
                                +
                                ROUND(
                                    (
                                        CAST(DT.OUT_TIME AS DATE)
                                        - TRUNC(CAST(DT.OUT_TIME AS DATE))
                                    ) * 1440 / 30
                                ) * 30 / 1440
                                +
                                CASE
                                    WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
                                    ELSE 0
                                END
                            )
                            -
                            GREATEST(
                                (
                                    TRUNC(CAST(DT.IN_TIME AS DATE))
                                    + (S.FROM_DATE - TRUNC(S.FROM_DATE))
                                    + (S.DURATION / 24)
                                ),
                                TRUNC(
                                    CAST(DT.OUT_TIME AS DATE)
                                    +
                                    CASE
                                        WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
                                        ELSE 0
                                    END
                                ) + 18 / 24
                            )
                        )
                    ELSE 0
                END

                +

                /* =====================================================
                   CASE 2:
                   IN_TIME is before SHIFT_START and is between
                   18:00 and 06:00.
                   Use rounded IN_TIME.
                   ===================================================== */
                CASE
                    WHEN (
                        TRUNC(CAST(DT.IN_TIME AS DATE))
                        +
                        ROUND(
                            (
                                CAST(DT.IN_TIME AS DATE)
                                - TRUNC(CAST(DT.IN_TIME AS DATE))
                            ) * 1440 / 30
                        ) * 30 / 1440
                    ) <
                    (
                        TRUNC(CAST(DT.IN_TIME AS DATE))
                        + (S.FROM_DATE - TRUNC(S.FROM_DATE))
                    )
                    AND
                    (
                        (
                            TRUNC(CAST(DT.IN_TIME AS DATE))
                            +
                            ROUND(
                                (
                                    CAST(DT.IN_TIME AS DATE)
                                    - TRUNC(CAST(DT.IN_TIME AS DATE))
                                ) * 1440 / 30
                            ) * 30 / 1440
                        ) >= TRUNC(CAST(DT.IN_TIME AS DATE)) + 18 / 24

                        OR

                        (
                            TRUNC(CAST(DT.IN_TIME AS DATE))
                            +
                            ROUND(
                                (
                                    CAST(DT.IN_TIME AS DATE)
                                    - TRUNC(CAST(DT.IN_TIME AS DATE))
                                ) * 1440 / 30
                            ) * 30 / 1440
                        ) < TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
                    )
                    THEN
                        CASE
                            /* 00:00 -> 06:00 */
                            WHEN (
                                TRUNC(CAST(DT.IN_TIME AS DATE))
                                +
                                ROUND(
                                    (
                                        CAST(DT.IN_TIME AS DATE)
                                        - TRUNC(CAST(DT.IN_TIME AS DATE))
                                    ) * 1440 / 30
                                ) * 30 / 1440
                            ) < TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
                            THEN
                                (
                                    TRUNC(CAST(DT.IN_TIME AS DATE)) + 6 / 24
                                )
                                -
                                (
                                    TRUNC(CAST(DT.IN_TIME AS DATE))
                                    +
                                    ROUND(
                                        (
                                            CAST(DT.IN_TIME AS DATE)
                                            - TRUNC(CAST(DT.IN_TIME AS DATE))
                                        ) * 1440 / 30
                                    ) * 30 / 1440
                                )

                            /* 18:00 -> midnight */
                            ELSE
                                (
                                    TRUNC(CAST(DT.IN_TIME AS DATE)) + 1
                                )
                                -
                                (
                                    TRUNC(CAST(DT.IN_TIME AS DATE))
                                    +
                                    ROUND(
                                        (
                                            CAST(DT.IN_TIME AS DATE)
                                            - TRUNC(CAST(DT.IN_TIME AS DATE))
                                        ) * 1440 / 30
                                    ) * 30 / 1440
                                )
                        END
                    ELSE 0
                END
            ),
            'HH24:MI'
        )
END AS OVER_TIME_AFTER_6,


--
--                    CASE
--                WHEN DT.IN_TIME IS NULL
--                  OR DT.OUT_TIME IS NULL
--                  OR S.FROM_DATE IS NULL
--                  OR S.DURATION IS NULL
--                THEN NULL
--
--                /* 1. Late overtime takes priority */
--                WHEN (
--                    CAST(DT.OUT_TIME AS DATE)
--                    + CASE
--                        WHEN DT.OUT_TIME < DT.IN_TIME THEN 1
--                        ELSE 0
--                      END
--                ) >
--                (
--                    TRUNC(CAST(DT.IN_TIME AS DATE))
--                    + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                    + (S.DURATION / 24)
--                )
--                THEN
--                    TO_CHAR(
--                        TRUNC(CAST(DT.IN_TIME AS DATE))
--                        + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                        + (S.DURATION / 24),
--                        'HH24:MI'
--                    )
--
--                /* 2. Otherwise, check early overtime */
--                WHEN (
--                    TRUNC(CAST(DT.IN_TIME AS DATE))
--                    +
--                    ROUND(
--                        (
--                            CAST(DT.IN_TIME AS DATE)
--                            - TRUNC(CAST(DT.IN_TIME AS DATE))
--                        ) * 1440 / 30
--                    ) * 30 / 1440
--                ) <
--                (
--                    TRUNC(CAST(DT.IN_TIME AS DATE))
--                    + (S.FROM_DATE - TRUNC(S.FROM_DATE))
--                )
--                THEN
--                    TO_CHAR(
--                        TRUNC(CAST(DT.IN_TIME AS DATE))
--                        +
--                        ROUND(
--                            (
--                                CAST(DT.IN_TIME AS DATE)
--                                - TRUNC(CAST(DT.IN_TIME AS DATE))
--                            ) * 1440 / 30
--                        ) * 30 / 1440,
--                        'HH24:MI'
--                    )
--
--                ELSE NULL
--            END AS OVERTIME_FROM,

CASE
    WHEN DT.IN_TIME IS NULL
      OR DT.OUT_TIME IS NULL
      OR S.FROM_DATE IS NULL
      OR S.DURATION IS NULL
    THEN NULL

    /* ==========================================
       1. LATE OVERTIME TAKES PRIORITY
       Round OUT_TIME to nearest 30 minutes first
       ========================================== */
    WHEN (
        TRUNC(CAST(DT.OUT_TIME AS DATE))
        +
        ROUND(
            (
                CAST(DT.OUT_TIME AS DATE)
                - TRUNC(CAST(DT.OUT_TIME AS DATE))
            ) * 1440 / 30
        ) * 30 / 1440
    ) >
    (
        TRUNC(CAST(DT.IN_TIME AS DATE))
        + (S.FROM_DATE - TRUNC(S.FROM_DATE))
        + (S.DURATION / 24)
    )
    THEN
        TO_CHAR(
            TRUNC(CAST(DT.IN_TIME AS DATE))
            + (S.FROM_DATE - TRUNC(S.FROM_DATE))
            + (S.DURATION / 24),
            'HH24:MI'
        )

    /* ==========================================
       2. OTHERWISE, CHECK EARLY OVERTIME
       Round IN_TIME to nearest 30 minutes first
       ========================================== */
    WHEN (
        TRUNC(CAST(DT.IN_TIME AS DATE))
        +
        ROUND(
            (
                CAST(DT.IN_TIME AS DATE)
                - TRUNC(CAST(DT.IN_TIME AS DATE))
            ) * 1440 / 30
        ) * 30 / 1440
    ) <
    (
        TRUNC(CAST(DT.IN_TIME AS DATE))
        + (S.FROM_DATE - TRUNC(S.FROM_DATE))
    )
    THEN
        TO_CHAR(
            TRUNC(CAST(DT.IN_TIME AS DATE))
            +
            ROUND(
                (
                    CAST(DT.IN_TIME AS DATE)
                    - TRUNC(CAST(DT.IN_TIME AS DATE))
                ) * 1440 / 30
            ) * 30 / 1440,
            'HH24:MI'
        )

    ELSE NULL
END AS OVERTIME_FROM,


--                NULL AS OVER_TIME,

                CASE
                    WHEN V.ID IS NOT NULL THEN 'VACATION'
                    WHEN DT.EMPLOYEE_ID IS NOT NULL THEN 'WORK'
--                    WHEN (UPPER(OFH.TARGET_NATIONALITY) = UPPER('ALL') OR UPPER(E.NATIONALITY) = UPPER(OFH.TARGET_NATIONALITY))
--                    AND (UPPER(E.RELIGION) = UPPER(OFH.TARGET_RELIGION) OR UPPER(OFH.TARGET_RELIGION) = UPPER('ALL'))
--                    THEN 'OFFICIAL HOLIDAY'
                    WHEN OFH.ID IS NOT NULL THEN 'OFFICIAL HOLIDAY'
                    WHEN RS.SHIFT_ID = 4 THEN 'OFF'
                    ELSE 'NO TRANSACTION'
                END AS DAY_STATUS,
  --  RP calculation

--        CASE
--                    WHEN RS.SHIFT_ID = 4 AND DT.IN_TIME IS NOT NULL AND DT.OUT_TIME IS NOT NULL THEN
--                        LPAD(
--                            EXTRACT(
--                                DAY FROM (
--                                    CASE
--                                        WHEN DT.OUT_TIME >= DT.IN_TIME
--                                        THEN DT.OUT_TIME - DT.IN_TIME
--                                        ELSE (DT.OUT_TIME + INTERVAL '1' DAY) - DT.IN_TIME
--                                    END
--                                )
--                            ) * 24
--                            +
--                            EXTRACT(
--                                HOUR FROM (
--                                    CASE
--                                        WHEN DT.OUT_TIME >= DT.IN_TIME
--                                        THEN DT.OUT_TIME - DT.IN_TIME
--                                        ELSE (DT.OUT_TIME + INTERVAL '1' DAY) - DT.IN_TIME
--                                    END
--                                )
--                            ),
--                            2,
--                            '0'
--                        )
--                        || ':' ||
--                        LPAD(
--                            EXTRACT(
--                                MINUTE FROM (
--                                    CASE
--                                        WHEN DT.OUT_TIME >= DT.IN_TIME
--                                        THEN DT.OUT_TIME - DT.IN_TIME
--                                        ELSE (DT.OUT_TIME + INTERVAL '1' DAY) - DT.IN_TIME
--                                    END
--                                )
--                            ),
--                            2,
--                            '0'
--                        )
--                END AS RP,
-- RP calculation: nearest 30-minute interval
-- RP calculation: round IN_TIME and OUT_TIME
-- to the nearest 30 minutes before calculating duration.
-- RP calculation: round IN_TIME and OUT_TIME
-- to the nearest 30 minutes before calculating duration.
CASE
    WHEN RS.SHIFT_ID = 4
     AND DT.IN_TIME IS NOT NULL
     AND DT.OUT_TIME IS NOT NULL
    THEN
        TO_CHAR(
            TRUNC(
                ROUND(
                    (
                        (
                            TRUNC(CAST(DT.OUT_TIME AS DATE))
                            + ROUND(
                                (
                                    CAST(DT.OUT_TIME AS DATE)
                                    - TRUNC(CAST(DT.OUT_TIME AS DATE))
                                ) * 48
                            ) / 48
                        )
                        -
                        (
                            TRUNC(CAST(DT.IN_TIME AS DATE))
                            + ROUND(
                                (
                                    CAST(DT.IN_TIME AS DATE)
                                    - TRUNC(CAST(DT.IN_TIME AS DATE))
                                ) * 48
                            ) / 48
                        )
                    ) * 1440
                ) / 60
            ),
            'FM00'
        )
        || ':' ||
        TO_CHAR(
            MOD(
                ROUND(
                    (
                        (
                            TRUNC(CAST(DT.OUT_TIME AS DATE))
                            + ROUND(
                                (
                                    CAST(DT.OUT_TIME AS DATE)
                                    - TRUNC(CAST(DT.OUT_TIME AS DATE))
                                ) * 48
                            ) / 48
                        )
                        -
                        (
                            TRUNC(CAST(DT.IN_TIME AS DATE))
                            + ROUND(
                                (
                                    CAST(DT.IN_TIME AS DATE)
                                    - TRUNC(CAST(DT.IN_TIME AS DATE))
                                ) * 48
                            ) / 48
                        )
                    ) * 1440
                ),
                60
            ),
            'FM00'
        )
    ELSE NULL
END AS RP,
                CASE
                    WHEN P.ID IS NOT NULL THEN 'PERMISSION'
                    ELSE 'NO PERMISSION IN THIS DAY'
                END AS PERMISSION_STATUS

            FROM EMPLOYEE E

            CROSS JOIN month_dates MD

            LEFT JOIN daily_transactions DT
                ON DT.EMPLOYEE_ID = E.ID
               AND DT.TRANSACTION_DATE = MD.TRANSACTION_DATE

            LEFT JOIN VACATION V
                ON V.EMPLOYEE_ID = E.ID
               AND MD.TRANSACTION_DATE BETWEEN TRUNC(V.FROM_DATE)
                                           AND TRUNC(V.TO_DATE)

            LEFT JOIN MISSION M
                ON M.EMPLOYEE_ID = E.ID
                AND MD.TRANSACTION_DATE BETWEEN TRUNC(M.FROM_DATE) AND TRUNC(M.TO_DATE)

            LEFT JOIN PERMISSION P
                ON P.EMPLOYEE_ID = E.ID
               AND TRUNC(P."DATE") = MD.TRANSACTION_DATE

            LEFT JOIN OFFICIAL_HOLIDAY OFH
            ON MD.TRANSACTION_DATE BETWEEN TRUNC(OFH.FROM_DATE) AND TRUNC(OFH.TO_DATE)
             AND (
            UPPER(OFH.TARGET_NATIONALITY) = 'ALL'
                OR UPPER(E.NATIONALITY) = UPPER(OFH.TARGET_NATIONALITY)
               )
               AND (
                    UPPER(OFH.TARGET_RELIGION) = 'ALL'
                    OR UPPER(E.RELIGION) = UPPER(OFH.TARGET_RELIGION)
               )

            LEFT JOIN rotation_calculation RC
            ON RC.EMPLOYEE_ID = E.ID
            and RC.TRANSACTION_DATE = MD.TRANSACTION_DATE

            LEFT JOIN PROJECT PRO ON E.PROJECT_ID = PRO.ID
            LEFT JOIN LOCATION LO ON E.LOCATION_ID = LO.ID
            LEFT JOIN DEPARTMENT DE ON E.DEPARTMENT_ID = DE.ID

            LEFT JOIN rotation_shift RS
                ON RS.ROTATION_ID = RC.ROTATION_ID
               AND RS.ROTATION_DAY = RC.ROTATION_DAY
            LEFT JOIN SHIFT S
                ON S.ID = RS.SHIFT_ID

            WHERE
                ( (
            P_EMPLOYEE_IDS IS NULL
            AND P_DEPARTMENT IS NULL
            AND P_LOCATION IS NULL
            AND P_PROJECT IS NULL
        )
        OR
                       (
                           P_EMPLOYEE_IDS IS NOT NULL
                           AND E.ID IN (
                               SELECT TO_NUMBER(COLUMN_VALUE)
                               FROM TABLE(APEX_STRING.SPLIT(P_EMPLOYEE_IDS, ':'))
                           )
                       )
                    OR (
                           P_DEPARTMENT IS NOT NULL
                           AND E.DEPARTMENT_ID = P_DEPARTMENT
                       )
                    OR (
                           P_LOCATION IS NOT NULL
                           AND E.LOCATION_ID = P_LOCATION
                       )
                    OR (
                           P_PROJECT IS NOT NULL
                           AND E.PROJECT_ID = P_PROJECT
                       )
                )

            ORDER BY E.EMPLOYEE_NUMBER, MD.TRANSACTION_DATE;

    END GET_TIME_SHEET_REPORT_MULTI;

    PROCEDURE POPULATE_MONTHLY_CACHE (
        P_YEAR        IN VARCHAR2,
        P_MONTH       IN VARCHAR2,
        P_LOCATION_ID IN NUMBER DEFAULT NULL,
        P_DEPARTMENT  IN VARCHAR2,
        P_LOCATION   IN VARCHAR2,
        P_PROJECT     IN VARCHAR2,
        P_BATCH_SIZE  IN NUMBER DEFAULT 100
    ) IS
        l_batch_ids   VARCHAR2(32767);
        l_cursor      SYS_REFCURSOR;
        l_batch_count NUMBER := 0;
        l_total_rows  NUMBER := 0;
        l_emp_count   NUMBER := 0;
        l_batch_size  NUMBER := NVL(P_BATCH_SIZE, 100);

        TYPE t_ts_rec IS RECORD (
            id                          NUMBER,
            employee_number             VARCHAR2(100),
            actual_transaction_date     DATE,
            transaction_date            DATE,
            name                        VARCHAR2(200),
            project_id                  NUMBER,
            project_name                VARCHAR2(200),
            location_id                 NUMBER,
            location_name               VARCHAR2(200),
            department_id               NUMBER,
            department_name             VARCHAR2(200),
            is_active                   VARCHAR2(10),
            grade_id                    NUMBER,
            last_timesheet_print_date   DATE,
            nationality                 VARCHAR2(100),
            religion                    VARCHAR2(100),
            print_timesheet             NUMBER,
            created_by                  VARCHAR2(100),
            creation_date               TIMESTAMP,
            last_updated_by             VARCHAR2(100),
            last_update_date            TIMESTAMP,
            permission_id               NUMBER,
            permission_type_id          NUMBER,
            permission_description      VARCHAR2(500),
            permission_from_time        TIMESTAMP,
            permission_to_time          TIMESTAMP,
            rotation_id                 NUMBER,
            rotation_start_date         DATE,
            rotation_days               NUMBER,
            rotation_day                NUMBER,
            shift_id                    NUMBER,
            in_time                     VARCHAR2(100),
            out_time                    VARCHAR2(100),
            worked_hours                VARCHAR2(100),
            over_time                   VARCHAR2(100),
            over_time_after_6           VARCHAR2(100),
            day_status                  VARCHAR2(100),
            rp                          VARCHAR2(100),
            permission_status           VARCHAR2(100)
        );
        TYPE t_ts_tab IS TABLE OF t_ts_rec;
        l_rows t_ts_tab;

        PROCEDURE process_cursor(p_cur IN OUT SYS_REFCURSOR) IS
        BEGIN
            LOOP
                FETCH p_cur BULK COLLECT INTO l_rows LIMIT 1000;
                EXIT WHEN l_rows.COUNT = 0;

                FOR i IN 1..l_rows.COUNT LOOP
                    INSERT INTO TIME_SHEET_CACHE (
                        EMP_NO, EMP_NAME, DEPARTMENT, LOCATION, PROJECT,
                        MONTH, YEAR, TRANSACTION_DAY_DATE, TIME_IN, TIME_OUT,
                        WORKED_HOURS, OVERTIME_BEFORE_SIX, OVERTIME_AFTER_SIX,
                        R_P, NATIONALITY, RELIGION, DAY_STATUS,
                        PERMISSION_STATUS, ROTATION_TYPE, ROTATION_DAY
                    ) VALUES (
                        l_rows(i).employee_number,
                        NVL(l_rows(i).name, 'Unknown'),
                        NVL(l_rows(i).department_name, 'N/A'),
                        NVL(l_rows(i).location_name, 'N/A'),
                        NVL(l_rows(i).project_name, 'N/A'),
                        TO_NUMBER(P_MONTH),
                        TO_NUMBER(P_YEAR),
                        l_rows(i).transaction_date,
                        l_rows(i).in_time,
                        l_rows(i).out_time,
                        l_rows(i).worked_hours,
                        l_rows(i).over_time,
                        l_rows(i).over_time_after_6,
                        l_rows(i).rp,
                        NVL(l_rows(i).nationality, 'N/A'),
                        NVL(l_rows(i).religion, 'N/A'),
                        NVL(l_rows(i).day_status, 'NO TRANSACTION'),
                        l_rows(i).permission_status,
                        NVL(TO_CHAR(l_rows(i).rotation_days), 'N/A'),
                        NVL(TO_CHAR(l_rows(i).rotation_day), 'N/A')
                    );

            END LOOP;
            l_total_rows := l_total_rows + l_rows.COUNT;
            end loop;
            CLOSE p_cur;
            COMMIT;
        END process_cursor;
    BEGIN
        IF P_YEAR IS NULL OR P_MONTH IS NULL THEN
            RAISE_APPLICATION_ERROR(-20090, 'Year and Month are required');
        END IF;

        -- 1. Clear existing cache for the given period
        IF P_LOCATION_ID IS NULL THEN
            DELETE FROM TIME_SHEET_CACHE
             WHERE YEAR = TO_NUMBER(P_YEAR)
               AND MONTH = TO_NUMBER(P_MONTH);
        ELSE
            DELETE FROM TIME_SHEET_CACHE
             WHERE YEAR = TO_NUMBER(P_YEAR)
               AND MONTH = TO_NUMBER(P_MONTH)
               AND LOCATION = (SELECT NAME FROM LOCATION WHERE ID = P_LOCATION_ID);
        END IF;
        COMMIT;

        -- 2. Process active employees in chunks
        FOR r IN (
            SELECT ID
              FROM EMPLOYEE
             WHERE IS_ACTIVE = '1'
               AND (P_LOCATION_ID IS NULL OR LOCATION_ID = P_LOCATION_ID)
             ORDER BY ID
        ) LOOP
            IF l_batch_ids IS NULL THEN
                l_batch_ids := TO_CHAR(r.ID);
            ELSE
                l_batch_ids := l_batch_ids || ':' || TO_CHAR(r.ID);
            END IF;
            l_batch_count := l_batch_count + 1;
            l_emp_count   := l_emp_count + 1;

            IF l_batch_count >= l_batch_size THEN
                GET_TIME_SHEET_REPORT_MULTI(
                    P_EMPLOYEE_IDS => l_batch_ids,
                    P_YEAR         => P_YEAR,
                    P_MONTH        => P_MONTH,
                    P_DEPARTMENT  => P_DEPARTMENT,
                    P_LOCATION    => P_LOCATION,
                    P_PROJECT      => P_PROJECT,
                    P_RESULT       => l_cursor
                );
                process_cursor(l_cursor);

                l_batch_ids   := NULL;
                l_batch_count := 0;
            END IF;
        END LOOP;

        -- Process remaining employees in last batch
        IF l_batch_ids IS NOT NULL THEN
            GET_TIME_SHEET_REPORT_MULTI(
                P_EMPLOYEE_IDS => l_batch_ids,
                P_YEAR         => P_YEAR,
                P_MONTH        => P_MONTH,
                P_DEPARTMENT   => P_DEPARTMENT,
                P_LOCATION     => P_LOCATION,
                P_PROJECT      => P_PROJECT,
                P_RESULT       => l_cursor
            );
            process_cursor(l_cursor);
        END IF;

        DBMS_OUTPUT.PUT_LINE('POPULATE_MONTHLY_CACHE completed: ' || l_emp_count ||
                             ' employees processed, ' || l_total_rows || ' rows inserted into TIME_SHEET_CACHE.');
    END POPULATE_MONTHLY_CACHE;


FUNCTION GET_TIME_SHEET_JSON_REPORT (
    P_EMPLOYEE_IDS IN VARCHAR2,
    P_YEAR         IN VARCHAR2,
    P_MONTH        IN VARCHAR2,
    P_DEPARTMENT   IN VARCHAR2,
    P_LOCATION     IN VARCHAR2,
    P_PROJECT      IN VARCHAR2
) RETURN CLOB
IS
    V_CLOB CLOB;
BEGIN

    SELECT JSON_ARRAYAGG(
               JSON_OBJECT(
                   'filename' VALUE 'TIME_SHEET_REPORT',

                   'data' VALUE (
                       SELECT JSON_OBJECT(
                                  'employees' VALUE (
                                      SELECT JSON_ARRAYAGG(
                                                 JSON_OBJECT(
                                                     'EMPLOYEE_NUMBER'
                                                         VALUE E.EMP_NO,

                                                     'EMPLOYEE_NAME'
                                                         VALUE E.EMP_NAME,

                                                     'DEPARTMENT'
                                                         VALUE E.DEPARTMENT,

                                                     'LOCATION'
                                                         VALUE E.LOCATION,

                                                     'PROJECT'
                                                         VALUE E.PROJECT,

--                                                     'MONTH'
--                                                         VALUE E.MONTH,
--
--                                                     'YEAR'
--                                                         VALUE E.YEAR,
                                                    'MONTH' VALUE TO_CHAR(
                                                        TO_DATE(E.MONTH || '-' || E.YEAR, 'MM-YYYY'),
                                                        'Mon-YYYY',
                                                        'NLS_DATE_LANGUAGE=ENGLISH'
                                                    ),
                                                    'TOTAL_OVERTIME_BEFORE_SIX'
                                                    VALUE E.TOTAL_OVERTIME_BEFORE_SIX,

                                                    'TOTAL_OVERTIME_AFTER_SIX'
                                                    VALUE E.TOTAL_OVERTIME_AFTER_SIX,

                                                    'TOTAL_RP'
                                                    VALUE E.TOTAL_RP,

                                                     'details'
                                                         VALUE E.DETAILS
                                                         FORMAT JSON

                                                     RETURNING CLOB
                                                 )
                                                 ORDER BY E.EMP_NO
                                                 RETURNING CLOB
                                             )
                                      FROM (
                                          SELECT
                                              T.EMP_NO,
                                              MAX(T.EMP_NAME)   AS EMP_NAME,
                                              MAX(T.DEPARTMENT) AS DEPARTMENT,
                                              MAX(T.LOCATION)   AS LOCATION,
                                              MAX(T.PROJECT)    AS PROJECT,
                                              MAX(T.MONTH)      AS MONTH,
                                              MAX(T.YEAR)       AS YEAR,

                                            /* Total overtime before six - decimal hours */
                                            ROUND(SUM(
                                                CASE
                                                    WHEN REGEXP_LIKE(
                                                        TRIM(T.OVERTIME_BEFORE_SIX),
                                                        '^[0-9]+:[0-5][0-9]$'
                                                    )
                                                    THEN
                                                        TO_NUMBER(
                                                            SUBSTR(
                                                                TRIM(T.OVERTIME_BEFORE_SIX),
                                                                1,
                                                                INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') - 1
                                                            )
                                                        )
                                                        +
                                                        TO_NUMBER(
                                                            SUBSTR(
                                                                TRIM(T.OVERTIME_BEFORE_SIX),
                                                                INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') + 1
                                                            )
                                                        ) / 60
                                                    ELSE 0
                                                END
                                                ), 1
                                            ) AS TOTAL_OVERTIME_BEFORE_SIX,

                                            /* Total overtime after six - decimal hours */
                                            ROUND(SUM(
                                                CASE
                                                    WHEN REGEXP_LIKE(
                                                        TRIM(T.OVERTIME_AFTER_SIX),
                                                        '^[0-9]+:[0-5][0-9]$'
                                                    )
                                                    THEN
                                                        TO_NUMBER(
                                                            SUBSTR(
                                                                TRIM(T.OVERTIME_AFTER_SIX),
                                                                1,
                                                                INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') - 1
                                                            )
                                                        )
                                                        +
                                                        TO_NUMBER(
                                                            SUBSTR(
                                                                TRIM(T.OVERTIME_AFTER_SIX),
                                                                INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') + 1
                                                            )
                                                        ) / 60
                                                    ELSE 0
                                                END
                                                ),1
                                            ) AS TOTAL_OVERTIME_AFTER_SIX,

                                            /* Total RP - sum of daily values rounded to nearest 30 minutes */
                                        ROUND(
                                            SUM(
                                                CASE
                                                    /* RP stored as HH:MM */
                                                    WHEN REGEXP_LIKE(
                                                             TRIM(T.R_P),
                                                             '^[0-9]+:[0-5][0-9]$'
                                                         )
                                                    THEN
                                                        ROUND(
                                                            (
                                                                TO_NUMBER(
                                                                    SUBSTR(
                                                                        TRIM(T.R_P),
                                                                        1,
                                                                        INSTR(TRIM(T.R_P), ':') - 1
                                                                    )
                                                                ) * 60
                                                                +
                                                                TO_NUMBER(
                                                                    SUBSTR(
                                                                        TRIM(T.R_P),
                                                                        INSTR(TRIM(T.R_P), ':') + 1
                                                                    )
                                                                )
                                                            ) / 30
                                                        ) / 2

                                                    /* RP already stored as decimal hours */
                                                    WHEN REGEXP_LIKE(
                                                             TRIM(T.R_P),
                                                             '^[0-9]+([.][0-9]+)?$'
                                                         )
                                                    THEN
                                                        ROUND(
                                                            TO_NUMBER(
                                                                TRIM(T.R_P),
                                                                '999999999999999D999999',
                                                                'NLS_NUMERIC_CHARACTERS=''.,'''
                                                            ) * 2
                                                        ) / 2

                                                    ELSE 0
                                                END
                                            ),
                                            1
                                        ) AS TOTAL_RP,


                                              JSON_ARRAYAGG(
                                                  JSON_OBJECT(
                                                      'DAY_NAME'
                                                          VALUE TO_CHAR(
                                                              T.TRANSACTION_DAY_DATE,
                                                              'DY',
                                                              'NLS_DATE_LANGUAGE=ENGLISH'
                                                          ),

                                                      'TRANSACTION_DATE'
                                                          VALUE TO_CHAR(
                                                              T.TRANSACTION_DAY_DATE,
                                                              'DD'
                                                          ),

                                                      'TIME_IN_HOURS' VALUE TO_NUMBER(SUBSTR(T.TIME_IN, 1, INSTR(T.TIME_IN, ':') - 1)),
                                                        'TIME_IN_MINS'  VALUE TO_NUMBER(SUBSTR(T.TIME_IN, INSTR(T.TIME_IN, ':') + 1, 2)),

                                                        'TIME_OUT_HOURS' VALUE TO_NUMBER(SUBSTR(T.TIME_OUT, 1, INSTR(T.TIME_OUT, ':') - 1)),
                                                        'TIME_OUT_MINS'  VALUE TO_NUMBER(SUBSTR(T.TIME_OUT, INSTR(T.TIME_OUT, ':') + 1, 2)),

                                                      'WORKED_HOURS' VALUE
                                                            CASE
                                                                WHEN REGEXP_LIKE(TRIM(T.WORKED_HOURS), '^[0-9]+:[0-5][0-9]$')
                                                                THEN TO_CHAR(
                                                                         TO_NUMBER(SUBSTR(T.WORKED_HOURS, 1, INSTR(T.WORKED_HOURS, ':') - 1))
                                                                         + TO_NUMBER(SUBSTR(T.WORKED_HOURS, INSTR(T.WORKED_HOURS, ':') + 1)) / 60,
                                                                         'FM999990.0'
                                                                     )
                                                                ELSE NULL
                                                            END,

--                                                    'OVERTIME_FROM' VALUE T.OVERTIME_FROM,
--
--                                                    'OVERTIME_TO' VALUE
--                                                        CASE
--                                                        WHEN REGEXP_LIKE(
--                                                                 TRIM(T.OVERTIME_FROM),
--                                                                 '^[0-9]{2}:[0-5][0-9]$'
--                                                             )
--                                                         AND REGEXP_LIKE(
--                                                                 TRIM(T.SHIFT_FROM_TIME),
--                                                                 '^[0-9]{2}:[0-5][0-9]$'
--                                                             )
--                                                         AND (
--                                                                TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                             ) <
--                                                             (
--                                                                TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 1, 2)) * 60
--                                                                + TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 4, 2))
--                                                             )
--                                                        THEN
--                                                            T.SHIFT_FROM_TIME
--
--                                                            WHEN REGEXP_LIKE(TRIM(T.TIME_OUT), '^[0-9]{2}:[0-5][0-9]$')
--                                                             AND REGEXP_LIKE(TRIM(T.OVERTIME_FROM), '^[0-9]{2}:[0-5][0-9]$')
--                                                             AND (
--                                                                    TO_NUMBER(SUBSTR(T.TIME_OUT, 1, 2)) * 60
--                                                                    + TO_NUMBER(SUBSTR(T.TIME_OUT, 4, 2))
--                                                                 ) >
--                                                                 (
--                                                                    TO_NUMBER(SUBSTR(T.OVERTIME_FROM, 1, 2)) * 60
--                                                                    + TO_NUMBER(SUBSTR(T.OVERTIME_FROM, 4, 2))
--                                                                 )
--                                                            THEN
--                                                                TO_CHAR(
--                                                                    TRUNC(SYSDATE)
--                                                                    +
--                                                                    ROUND(
--                                                                        (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                        ) / 30
--                                                                    ) * 30 / 1440,
--                                                                    'HH24:MI'
--                                                                )
--
--                                                            WHEN REGEXP_LIKE(TRIM(T.OVERTIME_BEFORE_SIX), '^[0-9]+:[0-5][0-9]$')
--                                                             AND REGEXP_LIKE(TRIM(T.TIME_OUT), '^[0-9]{2}:[0-5][0-9]$')
--                                                            THEN
--                                                                TO_CHAR(
--                                                                    ROUND(
--                                                                        (
--                                                                            TO_NUMBER(SUBSTR(T.TIME_OUT, 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(T.TIME_OUT, 4, 2))
--                                                                        ) / 30
--                                                                    ) * 30 / 1440 + TRUNC(SYSDATE),
--                                                                    'HH24:MI'
--                                                                )
--
--                                                            WHEN REGEXP_LIKE(TRIM(T.OVERTIME_AFTER_SIX), '^[0-9]+:[0-5][0-9]$')
--                                                            THEN
--                                                                TO_CHAR(
--                                                                    TO_DATE('18:00', 'HH24:MI')
--                                                                    +
--                                                                    ROUND(
--                                                                        (
--                                                                            TO_NUMBER(SUBSTR(T.OVERTIME_AFTER_SIX, 1,
--                                                                                INSTR(T.OVERTIME_AFTER_SIX, ':') - 1)) * 60
--                                                                            +
--                                                                            TO_NUMBER(SUBSTR(T.OVERTIME_AFTER_SIX,
--                                                                                INSTR(T.OVERTIME_AFTER_SIX, ':') + 1))
--                                                                        ) / 30
--                                                                    ) * 30 / 1440,
--                                                                    'HH24:MI'
--                                                                )
--
--                                                            ELSE ''
--                                                        END,


                                                    /* Overtime From - Hours */

/* Overtime From - Hours */
                                                    'OVERTIME_FROM_HOURS' VALUE
                                                        CASE
                                                            WHEN REGEXP_LIKE(
                                                                     TRIM(T.OVERTIME_FROM),
                                                                     '^[0-9]{2}:[0-5][0-9]$'
                                                                 )
                                                            THEN TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2))
                                                            ELSE NULL
                                                        END,

                                                    /* Overtime From - Minutes */
                                                    'OVERTIME_FROM_MINS' VALUE
                                                        CASE
                                                            WHEN REGEXP_LIKE(
                                                                     TRIM(T.OVERTIME_FROM),
                                                                     '^[0-9]{2}:[0-5][0-9]$'
                                                                 )
                                                            THEN TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
                                                            ELSE NULL
                                                        END,

--                                                    /* Overtime To - Hours */
--                                                    'OVERTIME_TO_HOURS' VALUE
--                                                        CASE
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.OVERTIME_FROM),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                            THEN
--                                                                CASE
--                                                                    /* Early overtime ends at shift start */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.SHIFT_FROM_TIME),
--                                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                                         )
--                                                                     AND (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                         ) <
--                                                                         (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 4, 2))
--                                                                         )
--                                                                    THEN TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 1, 2))
--
--                                                                    /* Late overtime ends at rounded TIME_OUT */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.TIME_OUT),
--                                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                                         )
--                                                                     AND (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                         ) >
--                                                                         (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                         )
--                                                                    THEN TRUNC(MOD(
--                                                                             ROUND(
--                                                                                 (
--                                                                                     TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                     + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                                 ) / 30
--                                                                             ) * 30,
--                                                                             1440
--                                                                         ) / 60)
--
--                                                                    /* Before 6 PM */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.OVERTIME_BEFORE_SIX),
--                                                                             '^[0-9]+:[0-5][0-9]$'
--                                                                         )
--                                                                     AND REGEXP_LIKE(
--                                                                             TRIM(T.TIME_OUT),
--                                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                                         )
--                                                                    THEN MOD(
--                                                                             ROUND(
--                                                                                 (
--                                                                                     TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                     + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                                 ) / 30
--                                                                             ) * 30,
--                                                                             1440
--                                                                         ) / 60
--
--                                                                    /* After 6 PM */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.OVERTIME_AFTER_SIX),
--                                                                             '^[0-9]+:[0-5][0-9]$'
--                                                                         )
--                                                                    THEN MOD(
--                                                                             18 * 60
--                                                                             + ROUND(
--                                                                                 (
--                                                                                     TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_AFTER_SIX), 1,
--                                                                                         INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') - 1)) * 60
--                                                                                     + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_AFTER_SIX),
--                                                                                         INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') + 1))
--                                                                                 ) / 30
--                                                                             ) * 30,
--                                                                             1440
--                                                                         ) / 60
--
--                                                                    ELSE NULL
--                                                                END
--                                                            ELSE NULL
--                                                        END,
--
--                                                    /* Overtime To - Minutes */
--                                                    'OVERTIME_TO_MINS' VALUE
--                                                        CASE
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.OVERTIME_FROM),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                            THEN
--                                                                CASE
--                                                                    /* Early overtime ends at shift start */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.SHIFT_FROM_TIME),
--                                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                                         )
--                                                                     AND (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                         ) <
--                                                                         (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 4, 2))
--                                                                         )
--                                                                    THEN TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 4, 2))
--
--                                                                    /* Late overtime ends at rounded TIME_OUT */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.TIME_OUT),
--                                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                                         )
--                                                                     AND (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                         ) >
--                                                                         (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                         )
--                                                                    THEN MOD(
--                                                                             MOD(
--                                                                                 ROUND(
--                                                                                     (
--                                                                                         TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                         + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                                     ) / 30
--                                                                                 ) * 30,
--                                                                                 1440
--                                                                             ),
--                                                                             60
--                                                                         )
--
--                                                                    /* Before 6 PM */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.OVERTIME_BEFORE_SIX),
--                                                                             '^[0-9]+:[0-5][0-9]$'
--                                                                         )
--                                                                     AND REGEXP_LIKE(
--                                                                             TRIM(T.TIME_OUT),
--                                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                                         )
--                                                                    THEN MOD(
--                                                                             MOD(
--                                                                                 ROUND(
--                                                                                     (
--                                                                                         TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                         + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                                     ) / 30
--                                                                                 ) * 30,
--                                                                                 1440
--                                                                             ),
--                                                                             60
--                                                                         )
--
--                                                                    /* After 6 PM */
--                                                                    WHEN REGEXP_LIKE(
--                                                                             TRIM(T.OVERTIME_AFTER_SIX),
--                                                                             '^[0-9]+:[0-5][0-9]$'
--                                                                         )
--                                                                    THEN MOD(
--                                                                             18 * 60
--                                                                             + ROUND(
--                                                                                 (
--                                                                                     TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_AFTER_SIX), 1,
--                                                                                         INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') - 1)) * 60
--                                                                                     + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_AFTER_SIX),
--                                                                                         INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') + 1))
--                                                                                 ) / 30
--                                                                             ) * 30,
--                                                                             60
--                                                                         )
--
--                                                                    ELSE NULL
--                                                                END
--                                                            ELSE NULL
--                                                        END,
                                            /* OVERTIME TO - HOURS */
                                            /* OVERTIME TO - HOURS */
'OVERTIME_TO_HOURS' VALUE
    CASE
        WHEN REGEXP_LIKE(
                 TRIM(T.OVERTIME_FROM),
                 '^[0-9]{2}:[0-5][0-9]$'
             )
        THEN
            TRUNC(
                MOD(
                    /* Starting time in minutes */
                    TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
                    + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))

                    /* Add total overtime before six */
                    + CASE
                        WHEN REGEXP_LIKE(
                                 TRIM(T.OVERTIME_BEFORE_SIX),
                                 '^[0-9]+:[0-5][0-9]$'
                             )
                        THEN
                            TO_NUMBER(SUBSTR(
                                TRIM(T.OVERTIME_BEFORE_SIX),
                                1,
                                INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') - 1
                            )) * 60
                            + TO_NUMBER(SUBSTR(
                                TRIM(T.OVERTIME_BEFORE_SIX),
                                INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') + 1
                            ))
                        ELSE 0
                      END

                    /* Add total overtime after six */
                    + CASE
                        WHEN REGEXP_LIKE(
                                 TRIM(T.OVERTIME_AFTER_SIX),
                                 '^[0-9]+:[0-5][0-9]$'
                             )
                        THEN
                            TO_NUMBER(SUBSTR(
                                TRIM(T.OVERTIME_AFTER_SIX),
                                1,
                                INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') - 1
                            )) * 60
                            + TO_NUMBER(SUBSTR(
                                TRIM(T.OVERTIME_AFTER_SIX),
                                INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') + 1
                            ))
                        ELSE 0
                      END,
                    1440
                ) / 60
            )
        ELSE NULL
    END,
--                                            'OVERTIME_TO_HOURS' VALUE
--                                                CASE
--                                                    WHEN REGEXP_LIKE(
--                                                             TRIM(T.OVERTIME_FROM),
--                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                         )
--                                                    THEN
--                                                        CASE
--                                                            /* Early overtime: end at shift start */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.SHIFT_FROM_TIME),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                             AND (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                 ) <
--                                                                 (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 4, 2))
--                                                                 )
--                                                            THEN
--                                                                TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 1, 2))
--
--                                                            /* Late overtime: use rounded TIME_OUT */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.TIME_OUT),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                             AND (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                 ) >
--                                                                 (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                 )
--                                                            THEN
--                                                                TRUNC(
--                                                                    MOD(
--                                                                        ROUND(
--                                                                            (
--                                                                                TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                            ) / 30
--                                                                        ) * 30,
--                                                                        1440
--                                                                    ) / 60
--                                                                )
--
--                                                            /* Before 6 PM */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.OVERTIME_BEFORE_SIX),
--                                                                     '^[0-9]+:[0-5][0-9]$'
--                                                                 )
--                                                             AND REGEXP_LIKE(
--                                                                     TRIM(T.TIME_OUT),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                            THEN
--                                                                TRUNC(
--                                                                    MOD(
--                                                                        ROUND(
--                                                                            (
--                                                                                TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                            ) / 30
--                                                                        ) * 30,
--                                                                        1440
--                                                                    ) / 60
--                                                                )
--
--                                                            /* After 6 PM: use rounded TIME_OUT */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.OVERTIME_AFTER_SIX),
--                                                                     '^[0-9]+:[0-5][0-9]$'
--                                                                 )
--                                                             AND REGEXP_LIKE(
--                                                                     TRIM(T.TIME_OUT),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                            THEN
--                                                                TRUNC(
--                                                                    MOD(
--                                                                        ROUND(
--                                                                            (
--                                                                                TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                            ) / 30
--                                                                        ) * 30,
--                                                                        1440
--                                                                    ) / 60
--                                                                )
--
--                                                            ELSE NULL
--                                                        END
--                                                    ELSE NULL
--                                                END,

                                            /* OVERTIME TO - MINUTES */
                                            /* OVERTIME TO - MINUTES */
'OVERTIME_TO_MINS' VALUE
    CASE
        WHEN REGEXP_LIKE(
                 TRIM(T.OVERTIME_FROM),
                 '^[0-9]{2}:[0-5][0-9]$'
             )
        THEN
            MOD(
                /* Starting time in minutes */
                TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
                + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))

                /* Add total overtime before six */
                + CASE
                    WHEN REGEXP_LIKE(
                             TRIM(T.OVERTIME_BEFORE_SIX),
                             '^[0-9]+:[0-5][0-9]$'
                         )
                    THEN
                        TO_NUMBER(SUBSTR(
                            TRIM(T.OVERTIME_BEFORE_SIX),
                            1,
                            INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') - 1
                        )) * 60
                        + TO_NUMBER(SUBSTR(
                            TRIM(T.OVERTIME_BEFORE_SIX),
                            INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') + 1
                        ))
                    ELSE 0
                  END

                /* Add total overtime after six */
                + CASE
                    WHEN REGEXP_LIKE(
                             TRIM(T.OVERTIME_AFTER_SIX),
                             '^[0-9]+:[0-5][0-9]$'
                         )
                    THEN
                        TO_NUMBER(SUBSTR(
                            TRIM(T.OVERTIME_AFTER_SIX),
                            1,
                            INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') - 1
                        )) * 60
                        + TO_NUMBER(SUBSTR(
                            TRIM(T.OVERTIME_AFTER_SIX),
                            INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') + 1
                        ))
                    ELSE 0
                  END,
                60
            )
        ELSE NULL
    END,
--                                            'OVERTIME_TO_MINS' VALUE
--                                                CASE
--                                                    WHEN REGEXP_LIKE(
--                                                             TRIM(T.OVERTIME_FROM),
--                                                             '^[0-9]{2}:[0-5][0-9]$'
--                                                         )
--                                                    THEN
--                                                        CASE
--                                                            /* Early overtime: end at shift start */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.SHIFT_FROM_TIME),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                             AND (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                 ) <
--                                                                 (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 4, 2))
--                                                                 )
--                                                            THEN
--                                                                TO_NUMBER(SUBSTR(TRIM(T.SHIFT_FROM_TIME), 4, 2))
--
--                                                            /* Late overtime: use rounded TIME_OUT */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.TIME_OUT),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                             AND (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                 ) >
--                                                                 (
--                                                                     TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 1, 2)) * 60
--                                                                     + TO_NUMBER(SUBSTR(TRIM(T.OVERTIME_FROM), 4, 2))
--                                                                 )
--                                                            THEN
--                                                                MOD(
--                                                                    ROUND(
--                                                                        (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                        ) / 30
--                                                                    ) * 30,
--                                                                    1440
--                                                                ) - TRUNC(
--                                                                    MOD(
--                                                                        ROUND(
--                                                                            (
--                                                                                TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                                + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                            ) / 30
--                                                                        ) * 30,
--                                                                        1440
--                                                                    ) / 60
--                                                                ) * 60
--
--                                                            /* Before 6 PM */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.OVERTIME_BEFORE_SIX),
--                                                                     '^[0-9]+:[0-5][0-9]$'
--                                                                 )
--                                                             AND REGEXP_LIKE(
--                                                                     TRIM(T.TIME_OUT),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                            THEN
--                                                                MOD(
--                                                                    ROUND(
--                                                                        (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                        ) / 30
--                                                                    ) * 30,
--                                                                    60
--                                                                )
--
--                                                            /* After 6 PM: use rounded TIME_OUT minutes */
--                                                            WHEN REGEXP_LIKE(
--                                                                     TRIM(T.OVERTIME_AFTER_SIX),
--                                                                     '^[0-9]+:[0-5][0-9]$'
--                                                                 )
--                                                             AND REGEXP_LIKE(
--                                                                     TRIM(T.TIME_OUT),
--                                                                     '^[0-9]{2}:[0-5][0-9]$'
--                                                                 )
--                                                            THEN
--                                                                MOD(
--                                                                    ROUND(
--                                                                        (
--                                                                            TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 1, 2)) * 60
--                                                                            + TO_NUMBER(SUBSTR(TRIM(T.TIME_OUT), 4, 2))
--                                                                        ) / 30
--                                                                    ) * 30,
--                                                                    60
--                                                                )
--
--                                                            ELSE NULL
--                                                        END
--                                                    ELSE NULL
--                                                END,

                                                      'OVERTIME_BEFORE_SIX'
                                                        VALUE CASE
                                                            WHEN REGEXP_LIKE(
                                                                TRIM(T.OVERTIME_BEFORE_SIX),
                                                                '^[0-9]+:[0-5][0-9]$'
                                                            )
                                                            THEN
                                                                CASE
                                                                    WHEN ROUND(
                                                                        TO_NUMBER(
                                                                            SUBSTR(
                                                                                TRIM(T.OVERTIME_BEFORE_SIX),
                                                                                1,
                                                                                INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') - 1
                                                                            )
                                                                        )
                                                                        +
                                                                        TO_NUMBER(
                                                                            SUBSTR(
                                                                                TRIM(T.OVERTIME_BEFORE_SIX),
                                                                                INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') + 1
                                                                            )
                                                                        ) / 60,
                                                                        1
                                                                    ) = 0
                                                                    THEN ''
                                                                    ELSE TO_CHAR(
                                                                        ROUND(
                                                                            TO_NUMBER(
                                                                                SUBSTR(
                                                                                    TRIM(T.OVERTIME_BEFORE_SIX),
                                                                                    1,
                                                                                    INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') - 1
                                                                                )
                                                                            )
                                                                            +
                                                                            TO_NUMBER(
                                                                                SUBSTR(
                                                                                    TRIM(T.OVERTIME_BEFORE_SIX),
                                                                                    INSTR(TRIM(T.OVERTIME_BEFORE_SIX), ':') + 1
                                                                                )
                                                                            ) / 60,
                                                                            1
                                                                        ),
                                                                        'FM999999990D0',
                                                                        'NLS_NUMERIC_CHARACTERS=''.,'''
                                                                    )
                                                                END
                                                            ELSE ''
                                                        END,

--


                                        'OVERTIME_AFTER_SIX'
                                            VALUE CASE
                                                WHEN REGEXP_LIKE(
                                                    TRIM(T.OVERTIME_AFTER_SIX),
                                                    '^[0-9]+:[0-5][0-9]$'
                                                )
                                                THEN
                                                    CASE
                                                        WHEN ROUND(
                                                            TO_NUMBER(
                                                                SUBSTR(
                                                                    TRIM(T.OVERTIME_AFTER_SIX),
                                                                    1,
                                                                    INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') - 1
                                                                )
                                                            )
                                                            +
                                                            TO_NUMBER(
                                                                SUBSTR(
                                                                    TRIM(T.OVERTIME_AFTER_SIX),
                                                                    INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') + 1
                                                                )
                                                            ) / 60,
                                                            1
                                                        ) = 0
                                                        THEN ''
                                                        ELSE TO_CHAR(
                                                            ROUND(
                                                                TO_NUMBER(
                                                                    SUBSTR(
                                                                        TRIM(T.OVERTIME_AFTER_SIX),
                                                                        1,
                                                                        INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') - 1
                                                                    )
                                                                )
                                                                +
                                                                TO_NUMBER(
                                                                    SUBSTR(
                                                                        TRIM(T.OVERTIME_AFTER_SIX),
                                                                        INSTR(TRIM(T.OVERTIME_AFTER_SIX), ':') + 1
                                                                    )
                                                                ) / 60,
                                                                1
                                                            ),
                                                            'FM999999990D0',
                                                            'NLS_NUMERIC_CHARACTERS=''.,'''
                                                        )
                                                    END
                                                ELSE ''
                                            END,


                                                      'RP' VALUE
                                                    CASE
                                                        WHEN REGEXP_LIKE(
                                                                 TRIM(T.R_P),
                                                                 '^[0-9]+:[0-5][0-9]$'
                                                             )
                                                        THEN
                                                            TO_CHAR(
                                                                ROUND(
                                                                    (
                                                                        TO_NUMBER(
                                                                            SUBSTR(
                                                                                TRIM(T.R_P),
                                                                                1,
                                                                                INSTR(TRIM(T.R_P), ':') - 1
                                                                            )
                                                                        ) * 60
                                                                        +
                                                                        TO_NUMBER(
                                                                            SUBSTR(
                                                                                TRIM(T.R_P),
                                                                                INSTR(TRIM(T.R_P), ':') + 1
                                                                            )
                                                                        )
                                                                    ) / 30
                                                                ) / 2,
                                                                'FM999999990.0'
                                                            )
                                                        ELSE NULL
                                                    END,

                                                      'NATIONALITY'
                                                          VALUE T.NATIONALITY,

                                                      'RELIGION'
                                                          VALUE T.RELIGION,

                                                      'DAY_STATUS' VALUE
                                                        CASE UPPER(T.DAY_STATUS)
                                                            WHEN 'WORK' THEN ''
                                                            WHEN 'OFF' THEN 'R'
                                                            WHEN 'NO TRANSACTION' THEN 'U'
                                                            WHEN 'VACATION' THEN 'H'
                                                            WHEN 'OFFICIAL HOLIDAY' THEN 'P'
                                                            ELSE T.DAY_STATUS
                                                        END
                                                        ||
                                                        CASE
                                                            WHEN T.PERMISSION_STATUS IS NOT NULL AND  T.PERMISSION_STATUS = 'PERMISSION' AND T.PERMISSION_TYPE_ID = 1 THEN 'PP:' || T.PERMISSION_DESCRIPTION
                                                            WHEN T.PERMISSION_STATUS IS NOT NULL AND  T.PERMISSION_STATUS = 'PERMISSION' AND T.PERMISSION_TYPE_ID = 2 THEN 'CP:' || T.PERMISSION_DESCRIPTION
                                                            WHEN T.PERMISSION_STATUS = 'NO PERMISSION IN THIS DAY' THEN ''
                                                            ELSE ''
                                                        END
                                                        ,

                                                      'PERMISSION_STATUS'
                                                          VALUE T.PERMISSION_STATUS,

                                                      'ROTATION_TYPE'
                                                          VALUE T.ROTATION_TYPE,

                                                      'ROTATION_DAY'
                                                          VALUE T.ROTATION_DAY

                                                      RETURNING CLOB
                                                  )
                                                  ORDER BY
                                                      T.TRANSACTION_DAY_DATE,
                                                      T.ID
                                                  RETURNING CLOB
                                              ) AS DETAILS

                                          FROM TIME_SHEET_CACHE T

                                          LEFT JOIN DEPARTMENT D
                                              ON UPPER(D.NAME) =
                                                 UPPER(T.DEPARTMENT)

                                          LEFT JOIN LOCATION L
                                              ON UPPER(L.NAME) =
                                                 UPPER(T.LOCATION)

                                          LEFT JOIN PROJECT PR
                                              ON UPPER(PR.NAME) =
                                                 UPPER(T.PROJECT)

                                          WHERE T.MONTH = TO_NUMBER(P_MONTH)
                                            AND T.YEAR  = TO_NUMBER(P_YEAR)

                                            AND EXISTS (
                                                SELECT 1
                                                FROM EMPLOYEE E_ACTIVE
                                                WHERE E_ACTIVE.EMPLOYEE_NUMBER = T.EMP_NO
                                                  AND E_ACTIVE.IS_ACTIVE = 1
                                            )

                                            /* Employee filter */
                                            AND (
                                                P_EMPLOYEE_IDS IS NULL
                                                OR T.EMP_NO IN (
                                                    SELECT E2.EMPLOYEE_NUMBER
                                                    FROM EMPLOYEE E2
                                                    WHERE E2.ID IN (
                                                        SELECT TO_NUMBER(COLUMN_VALUE)
                                                        FROM TABLE(
                                                            APEX_STRING.SPLIT(
                                                                P_EMPLOYEE_IDS,
                                                                ':'
                                                            )
                                                        )
                                                    )
                                                )
                                            )

                                            /* Department filter */
                                            AND (
                                                P_DEPARTMENT IS NULL
                                                OR D.ID = P_DEPARTMENT
                                            )

                                            /* Location filter */
                                            AND (
                                                P_LOCATION IS NULL
                                                OR L.ID = P_LOCATION
                                            )

                                            /* Project filter */
                                            AND (
                                                P_PROJECT IS NULL
                                                OR PR.ID = P_PROJECT
                                            )

                                          GROUP BY T.EMP_NO
                                      ) E
                                  )
                                  FORMAT JSON
                                  RETURNING CLOB
                              )
                       FROM DUAL
                   )
                   FORMAT JSON
                   RETURNING CLOB
               )
               RETURNING CLOB
           )
      INTO V_CLOB
      FROM DUAL;

    RETURN V_CLOB;

END GET_TIME_SHEET_JSON_REPORT;


END TIME_SHEET_REPORT_PKG;
/
