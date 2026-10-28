
  CREATE OR REPLACE EDITIONABLE FUNCTION "TMS"."GET_EMPLOYEE_TIMESHEET" (
    p_location_id number default null,
    p_employee_id number default null,
    p_month date default null,
    p_work_date date default null
) return clob sql_macro(table) as
    /* This Oracle version cannot resolve a SQL_MACRO(TABLE) function's own
       parameters when they are referenced inside a WITH-clause CTE (only
       in the query's outermost, WITH-free scope) -- verified experimentally
       against this database (parameters visible in a bare "select ... from
       dual", not visible once the same expression sits inside "with x as
       (select ...)" at any nesting depth). The whole calculation below is
       one WITH chain, so the parameters are resolved to literals here, in
       plain PL/SQL, before the CTE text is built. All four parameters are
       NUMBER/DATE (never free text), so embedding them as typed SQL
       literals carries no SQL-injection risk. */
    c_horizon_min constant date := trunc(systimestamp) - 30;
    c_horizon_max constant date := trunc(systimestamp);
    l_min_day date;
    l_max_day date;
    l_location_pred varchar2(60);
    l_employee_pred varchar2(60);
    l_txn_employee_pred varchar2(60);
    l_txn_location_pred varchar2(120);
begin
    l_min_day := greatest(c_horizon_min,
                           nvl(case when p_month is not null then trunc(p_month, 'MM') end, c_horizon_min),
                           nvl(case when p_work_date is not null then trunc(p_work_date) end, c_horizon_min));
    l_max_day := least(c_horizon_max,
                        nvl(case when p_month is not null then add_months(trunc(p_month, 'MM'), 1) - 1 end, c_horizon_max),
                        nvl(case when p_work_date is not null then trunc(p_work_date) end, c_horizon_max));
    l_location_pred := case when p_location_id is null then '1=1'
                        else 'e.LOCATION_ID = ' || to_char(p_location_id) end;
    l_employee_pred := case when p_employee_id is null then '1=1'
                        else 'e.ID = ' || to_char(p_employee_id) end;
    l_txn_employee_pred := case when p_employee_id is null then '1=1'
                            else 't.EMPLOYEE_ID = ' || to_char(p_employee_id) end;
    l_txn_location_pred := case when p_location_id is null then '1=1'
                            else 't.EMPLOYEE_ID in (select ID from EMPLOYEE where LOCATION_ID = '
                                 || to_char(p_location_id) || ')' end;

    return
'with
  bounds as (
    select date ''' || to_char(l_min_day, 'YYYY-MM-DD') || ''' as min_day,
           date ''' || to_char(l_max_day, 'YYYY-MM-DD') || ''' as max_day
      from dual
  ),
  calendar as (
    select b.min_day + level - 1 as work_date
      from bounds b
    connect by level <= b.max_day - b.min_day + 1
  ),
  employee_days as (
    -- CONNECT BY row-generators are estimated by the optimizer as a single
    -- row regardless of actual iteration count, which understates this
    -- cross join by ~31x and misdirects every join built on top of it.
    -- The cardinality hint corrects only the optimizer''s cost estimate; it
    -- cannot change query results.
    select /*+ cardinality(c 31) */ e.ID as employee_id, e.EMPLOYEE_NUMBER, e.NAME as employee_name,
           e.LOCATION_ID, e.DEPARTMENT_ID, e.PROJECT_ID, e.GRADE_ID,
           e.NATIONALITY, e.RELIGION, e.PRINT_TIMESHEET, c.work_date
      from EMPLOYEE e
      cross join calendar c
     where e.IS_ACTIVE = ''1''
       and ' || l_location_pred || '
       and ' || l_employee_pred || '
  ),
' || q'[
  rotation_candidates as (
    select ed.employee_id, ed.work_date, h.ROTATION_ID, h.STARTED,
           row_number() over (
             partition by ed.employee_id, ed.work_date
             order by h.STARTED desc, h.ID desc
           ) as rn
      from employee_days ed
      join ROTATION_HISTORY h
        on h.EMPLOYEE_ID = ed.employee_id
       and h.STARTED < cast(ed.work_date + 1 as timestamp)
  ),
  selected_rotation as (
    select employee_id, work_date, rotation_id
      from rotation_candidates
     where rn = 1
  ),
  scheduled_days as (
    select ed.*, sr.rotation_id, rp.NAME as rotation_name,
           rp.DAYS as rotation_days, rp.START_DATE as rotation_start_date,
           rp.WORK_TYPE,
           case
             when rp.ID is null or rp.DAYS is null or rp.DAYS = 0 then null
             else mod(
                    case
                      when ed.work_date - trunc(rp.START_DATE) < 0
                      then ed.work_date - trunc(rp.START_DATE) + 7
                      else ed.work_date - trunc(rp.START_DATE)
                    end,
                    rp.DAYS
                  ) + 1
           end as rotation_day_number
      from employee_days ed
      left join selected_rotation sr
        on sr.employee_id = ed.employee_id
       and sr.work_date = ed.work_date
      left join ROTATION_PLAN rp on rp.ID = sr.rotation_id
  ),
  plan_shifts as (
    select sd.*, rd.SHIFT_ID as rotation_shift_id,
           a.ID as alternate_shift_id, a.SHIFT_ID as alternate_shift_id_value
      from scheduled_days sd
      left join ROTATION_DAY rd
        on rd.ROTATION_ID = sd.rotation_id
       and rd.DAY = sd.rotation_day_number
      left join ALTERNATE_SHIFT a
        on a.EMPLOYEE_ID = sd.employee_id
       and trunc(a."DATE") = sd.work_date
  ),
  shift_rows as (
    select ps.*,
           coalesce(ps.alternate_shift_id_value, ps.rotation_shift_id) as shift_id,
           s.NAME as shift_name, s.DURATION as shift_duration,
           case when s.IS_OFF = '1' then 'Y' else 'N' end as shift_is_off,
           s.FROM_DATE as shift_from_date,
           extract(hour from s.FROM_DATE) * 3600
             + extract(minute from s.FROM_DATE) * 60
             + extract(second from s.FROM_DATE) as shift_start_seconds
      from plan_shifts ps
      left join SHIFT s
        on s.ID = coalesce(ps.alternate_shift_id_value, ps.rotation_shift_id)
  ),
  windows as (
    select sr.*,
           cast(sr.work_date as timestamp)
             + numtodsinterval(sr.shift_start_seconds, 'SECOND') as shift_start,
           cast(sr.work_date as timestamp)
             + numtodsinterval(sr.shift_start_seconds + sr.shift_duration * 3600, 'SECOND') as shift_end,
           cast(sr.work_date as timestamp)
             + numtodsinterval(sr.shift_start_seconds - ((24 - sr.shift_duration) / 2) * 3600, 'SECOND') as window_start,
           cast(sr.work_date as timestamp)
             + numtodsinterval(sr.shift_start_seconds + sr.shift_duration * 3600
                               + ((24 - sr.shift_duration) / 2) * 3600, 'SECOND') as window_end
      from shift_rows sr
  ),
  transaction_rounded as (
    select /*+ materialize */ t.ID, t.EMPLOYEE_ID, t.TYPE, t."DATE",
           cast(loc.lt as date) as punch_date,
           trunc(cast(loc.lt as date)) as calendar_date,
           case
             when to_number(to_char(loc.lt, 'MI')) < 15
               then cast(trunc(loc.lt, 'HH') as date)
             when to_number(to_char(loc.lt, 'MI')) < 45
               then cast(trunc(loc.lt, 'HH') as date) + 30 / 1440
             else cast(trunc(loc.lt, 'HH') as date) + 1 / 24
           end as rounded_punch_date
      from "TRANSACTION" t
      cross apply (
        select APP_CONFIG_PKG.to_local_timestamp(t."DATE") as lt from dual
      ) loc
     where t."DATE" >= from_tz(cast(trunc(systimestamp) - 31 as timestamp), 'UTC')
       and t."DATE" < from_tz(cast(trunc(systimestamp) + 1 as timestamp), 'UTC')
       and ]' || l_txn_employee_pred || '
       and ' || l_txn_location_pred || q'[
  ),
  punch_aggregate as (
    select w.employee_id, w.work_date,
           min(case when t.TYPE = '0' then t.punch_date end) as actual_in,
           max(case when t.TYPE = '1' then t.punch_date end) as actual_out,
           min(case when t.TYPE = '0' then t.rounded_punch_date end) as rounded_in,
           max(case when t.TYPE = '1' then t.rounded_punch_date end) as rounded_out,
           count(t.ID) as transaction_count
      from windows w
      left join transaction_rounded t
        on t.EMPLOYEE_ID = w.employee_id
       and w.window_start is not null
       and t.punch_date between cast(w.window_start as date) and cast(w.window_end as date)
     group by w.employee_id, w.work_date
  ),
  flags as (
    /* Each source table is visited once via OUTER APPLY instead of once per
       exists-check and once per scalar-value lookup (13 correlated
       accesses reduced to 9), preserving the original "first by ID" tie-
       break and every filter predicate exactly. This changes only how the
       optimizer can plan the access, never which row is picked or what
       value it returns. */
    select w.*,
           pa.actual_in, pa.actual_out, pa.rounded_in, pa.rounded_out, pa.transaction_count,
           case when hol.holiday_id is not null then 'Y' else 'N' end as is_holiday,
           hol.holiday_name,
           case when vac.vacation_id is not null then 'Y' else 'N' end as is_vacation_record,
           vac.vacation_code,
           case when mis.mission_id is not null then 'Y' else 'N' end as is_mission,
           mis.mission_description,
           case when trn.training_id is not null then 'Y' else 'N' end as is_training,
           trn.training_description,
           case when comp_perm.permission_id is not null then 'Y' else 'N' end as is_company_permission,
           pers_perm.personal_permission_hours,
           perm_remark.permission_remark,
           slv.special_leave_name,
           aot.approved_overtime_remark
      from windows w
      join punch_aggregate pa
        on pa.employee_id = w.employee_id and pa.work_date = w.work_date
      outer apply (
        select h.ID as holiday_id, h.NAME as holiday_name
          from OFFICIAL_HOLIDAY h
         where h.FROM_DATE < cast(w.work_date + 1 as timestamp)
           and h.TO_DATE >= cast(w.work_date as timestamp)
           and (h.TARGET_NATIONALITY = w.NATIONALITY or h.TARGET_NATIONALITY = 'All')
           and (h.TARGET_RELIGION = w.RELIGION or h.TARGET_RELIGION = 'All')
           and (h.WORK_TYPE = w.WORK_TYPE or h.WORK_TYPE = 'All')
         order by h.ID fetch first 1 row only
      ) hol
      outer apply (
        select v.ID as vacation_id, vt.CODE as vacation_code
          from VACATION v join VACATION_TYPE vt on vt.ID = v.TYPE_ID
         where v.EMPLOYEE_ID = w.employee_id
           and v.FROM_DATE < cast(w.work_date + 1 as timestamp)
           and v.TO_DATE >= cast(w.work_date as timestamp)
         order by v.ID fetch first 1 row only
      ) vac
      outer apply (
        select m.ID as mission_id, substr(m.DESCRIPTION, 1, 30) as mission_description
          from MISSION m
         where m.EMPLOYEE_ID = w.employee_id
           and m.FROM_DATE < cast(w.work_date + 1 as timestamp)
           and m.TO_DATE >= cast(w.work_date as timestamp)
         order by m.ID fetch first 1 row only
      ) mis
      outer apply (
        select tr.ID as training_id, substr(tr.DESCRIPTION, 1, 30) as training_description
          from TRAINING tr
         where tr.EMPLOYEE_ID = w.employee_id
           and tr.FROM_DATE < cast(w.work_date + 1 as timestamp)
           and tr.TO_DATE >= cast(w.work_date as timestamp)
         order by tr.ID fetch first 1 row only
      ) trn
      outer apply (
        select p.ID as permission_id
          from PERMISSION p join PERMISSION_TYPE pt on pt.ID = p.TYPE_ID
         where p.EMPLOYEE_ID = w.employee_id
           and trunc(p."DATE") = w.work_date
           and pt.NAME = 'Company'
         order by p.ID fetch first 1 row only
      ) comp_perm
      outer apply (
        select (p.TO_TIME - p.FROM_TIME) * 24 as personal_permission_hours
          from PERMISSION p join PERMISSION_TYPE pt on pt.ID = p.TYPE_ID
         where p.EMPLOYEE_ID = w.employee_id
           and trunc(p."DATE") = w.work_date
           and pt.NAME = 'Personal'
         order by p.ID fetch first 1 row only
      ) pers_perm
      outer apply (
        select pt.NAME || ':' ||
               to_char(p.FROM_TIME, 'HH24:MI') || '-' || to_char(p.TO_TIME, 'HH24:MI') as permission_remark
          from PERMISSION p join PERMISSION_TYPE pt on pt.ID = p.TYPE_ID
         where p.EMPLOYEE_ID = w.employee_id
           and trunc(p."DATE") = w.work_date
         order by p.ID fetch first 1 row only
      ) perm_remark
      outer apply (
        select st.NAME as special_leave_name
          from SPECIAL_LEAVE sl join SPECIAL_LEAVE_TYPE st on st.ID = sl.TYPE_ID
         where sl.EMPLOYEE_ID = w.employee_id
           and sl.FROM_DATE < cast(w.work_date + 1 as timestamp)
           and sl.TO_DATE >= cast(w.work_date as timestamp)
         order by sl.ID fetch first 1 row only
      ) slv
      outer apply (
        select 'AOT:' || to_char(ao.FROM_TIME, 'HH24:MI') || '-' || to_char(ao.TO_TIME, 'HH24:MI') as approved_overtime_remark
          from APPROVED_OVERTIME ao
         where ao.EMPLOYEE_ID = w.employee_id
           and trunc(ao."DATE") = w.work_date
         order by ao.ID fetch first 1 row only
      ) aot
  ),
  day_ordered as (
    select tr.*,
           lag(tr.TYPE) over (
             partition by tr.EMPLOYEE_ID, tr.calendar_date
             order by tr.punch_date, tr.ID
           ) as previous_type
      from transaction_rounded tr
  ),
  day_clean as (
    select d.*
      from day_ordered d
     where d.previous_type is null or d.previous_type <> d.TYPE
  ),
  day_pairs as (
    select d.*,
           lead(d.TYPE) over (
             partition by d.EMPLOYEE_ID, d.calendar_date
             order by d.punch_date, d.ID
           ) as next_type,
           lead(d.rounded_punch_date) over (
             partition by d.EMPLOYEE_ID, d.calendar_date
             order by d.punch_date, d.ID
           ) as next_rounded_punch_date
      from day_clean d
  ),
  holiday_rest as (
    select d.EMPLOYEE_ID as employee_id, d.calendar_date as work_date,
           round(sum(
             case when d.TYPE = '0' and d.next_type = '1'
                  then greatest(0, (d.next_rounded_punch_date - d.rounded_punch_date) * 24)
                  when d.TYPE = '0'
                  then greatest(0, (d.calendar_date + 1 - d.rounded_punch_date) * 24)
                  else 0
             end
           ), 2) as rest_hours
      from day_pairs d
     group by d.EMPLOYEE_ID, d.calendar_date
  ),
  normalized as (
    select f.*,
           case when f.is_holiday = 'Y'
                then nvl(hr.rest_hours, 0)
                when f.shift_is_off = 'Y'
                 and f.rounded_in is not null
                 and f.rounded_out is not null
                then round(greatest(0,
                       (f.rounded_out - f.rounded_in
                        + case when f.rounded_out < f.rounded_in then 1 else 0 end) * 24), 2)
                else 0
           end as rest_hours,
           case
             when f.actual_in is null then null
             when to_number(to_char(f.actual_in, 'MI')) < 15
               then cast(trunc(f.actual_in, 'HH') as timestamp)
             when to_number(to_char(f.actual_in, 'MI')) < 45
               then cast(trunc(f.actual_in, 'HH') as timestamp) + numtodsinterval(30, 'MINUTE')
             else cast(trunc(f.actual_in, 'HH') as timestamp) + numtodsinterval(60, 'MINUTE')
           end as computed_in,
           case
             when f.actual_out is null then null
             when to_number(to_char(f.actual_out, 'MI')) < 15
               then cast(trunc(f.actual_out, 'HH') as timestamp)
             when to_number(to_char(f.actual_out, 'MI')) < 45
               then cast(trunc(f.actual_out, 'HH') as timestamp) + numtodsinterval(30, 'MINUTE')
             else cast(trunc(f.actual_out, 'HH') as timestamp) + numtodsinterval(60, 'MINUTE')
           end as computed_out
      from flags f
      left join holiday_rest hr
        on hr.employee_id = f.employee_id
       and hr.work_date = f.work_date
  ),
  morning_exception as (
    select n.*,
           case
             when n.shift_start_seconds = 27000
              and n.shift_duration = 8
              and n.actual_in between cast(n.work_date as timestamp) + numtodsinterval(26100, 'SECOND')
                                   and cast(n.work_date as timestamp) + numtodsinterval(29640, 'SECOND')
             then cast(n.work_date as timestamp) + numtodsinterval(27000, 'SECOND')
             else n.computed_in
           end as final_computed_in
      from normalized n
  ),
  calculated as (
    select m.*,
           case when m.final_computed_in is not null and m.computed_out is not null
                and m.computed_out > m.final_computed_in
                then case when m.shift_is_off = 'N' and m.is_holiday = 'N'
                                and m.is_vacation_record = 'N'
                                and m.is_mission = 'N' and m.is_training = 'N'
                          then round(
                                 extract(day from (least(m.computed_out, m.shift_end)
                                                   - greatest(m.final_computed_in, m.shift_start))) * 24
                                 + extract(hour from (least(m.computed_out, m.shift_end)
                                                   - greatest(m.final_computed_in, m.shift_start)))
                                 + extract(minute from (least(m.computed_out, m.shift_end)
                                                   - greatest(m.final_computed_in, m.shift_start))) / 60
                                 + extract(second from (least(m.computed_out, m.shift_end)
                                                   - greatest(m.final_computed_in, m.shift_start))) / 3600, 1)
                          else null end
                else null end as standard_hours,
           case when m.shift_is_off = 'N' and m.is_holiday = 'N'
                         and m.is_vacation_record = 'N' and m.is_mission = 'N'
                         and m.is_training = 'N' and m.final_computed_in is not null
                         and m.computed_out is not null and m.computed_out > m.final_computed_in
                then round(greatest(0,
                       extract(day from (m.shift_start - m.final_computed_in)) * 24
                       + extract(hour from (m.shift_start - m.final_computed_in))
                       + extract(minute from (m.shift_start - m.final_computed_in)) / 60
                       + extract(second from (m.shift_start - m.final_computed_in)) / 3600), 2)
                else 0 end as early_hours,
           case when m.shift_is_off = 'N' and m.is_holiday = 'N'
                         and m.is_vacation_record = 'N' and m.is_mission = 'N'
                         and m.is_training = 'N' and m.final_computed_in is not null
                         and m.computed_out is not null and m.computed_out > m.final_computed_in
                then round(greatest(0,
                       extract(day from (m.computed_out - m.shift_end)) * 24
                       + extract(hour from (m.computed_out - m.shift_end))
                       + extract(minute from (m.computed_out - m.shift_end)) / 60
                       + extract(second from (m.computed_out - m.shift_end)) / 3600), 2)
                else 0 end as late_hours
      from morning_exception m
  ),
  overtime_intervals as (
    select c.*,
           case
             when c.early_hours > 0 or c.late_hours > 0
             then case when c.early_hours > c.late_hours
                       then c.final_computed_in
                       else c.shift_end
                  end
           end as overtime_start,
           case
             when c.early_hours > 0 or c.late_hours > 0
             then case when c.early_hours > c.late_hours
                       then c.shift_start
                       else c.computed_out
                  end
           end as overtime_end
      from calculated c
  ),
  overtime_dates as (
    select oi.*,
           cast(oi.overtime_start as date) as overtime_start_date,
           cast(oi.overtime_end as date) as overtime_end_date,
           trunc(cast(oi.overtime_start as date)) as overtime_start_day,
           trunc(cast(oi.overtime_end as date)) as overtime_end_day
      from overtime_intervals oi
  ),
  overtime_daytime as (
    select od.*,
           case
             when od.overtime_start_date is null
               or od.overtime_end_date is null
               or od.overtime_end_date < od.overtime_start_date
             then 0
             else greatest(0,
                    (least(od.overtime_end_date, od.overtime_start_day + 19 / 24)
                     - greatest(od.overtime_start_date, od.overtime_start_day + 7 / 24)) * 24)
                  + case when od.overtime_end_day > od.overtime_start_day
                         then greatest(0,
                                (least(od.overtime_end_date, od.overtime_end_day + 19 / 24)
                                 - greatest(od.overtime_start_date, od.overtime_end_day + 7 / 24)) * 24)
                         else 0
                    end
                  + greatest(0, (od.overtime_end_day - od.overtime_start_day - 1) * 12)
           end as overtime_daytime_hours,
           case
             when od.overtime_start_date is null
               or od.overtime_end_date is null
               or od.overtime_end_date < od.overtime_start_date
             then 0
             else (od.overtime_end_date - od.overtime_start_date) * 24
           end as overtime_total_hours
      from overtime_dates od
  ),
  final_rows as (
    select o.*,
           case when o.shift_id is null then 'MISSING_ROTATION'
                else 'OK' end as calculation_status,
           case when o.shift_is_off = 'N' and o.is_holiday = 'N'
                     and o.is_vacation_record = 'N' and o.is_mission = 'N'
                     and o.is_training = 'N' and o.is_company_permission = 'N'
                     and (o.actual_in is null or o.actual_out is null)
                then 'Y' else 'N' end as is_absent,
           case when o.shift_is_off = 'Y'
                     and (o.is_vacation_record = 'Y' or o.is_mission = 'Y' or o.is_training = 'Y')
                then 8
                else round(o.overtime_daytime_hours * 1.35
                           + greatest(0, o.overtime_total_hours - o.overtime_daytime_hours) * 1.7
                           + o.rest_hours * 2, 2)
           end as calculated_hours,
           case
             when o.special_leave_name is not null
               then case when o.special_leave_name = 'Unpaid' then 'U' else o.special_leave_name end
             when o.is_vacation_record = 'Y' then o.vacation_code
             when o.is_training = 'Y' then 'T' || case when o.training_description is not null then ':' || o.training_description end
             when o.is_mission = 'Y' then 'B' || case when o.mission_description is not null then ':' || o.mission_description end
             when o.is_company_permission = 'Y' then 'CP'
             when o.is_holiday = 'Y' then 'P: ' || o.holiday_name
             when o.shift_is_off = 'Y' then 'R'
             when o.shift_id is null then 'ERR: no rotation plan'
             when o.actual_in is null or o.actual_out is null then 'U'
             else null
           end as base_remark
      from overtime_daytime o
  )
select employee_id, employee_number, employee_name, location_id, department_id, project_id, grade_id,
       nationality, religion, print_timesheet,
       work_date, rotation_id, rotation_name, rotation_day_number,
       rotation_shift_id, alternate_shift_id, shift_id, shift_name, shift_duration,
       shift_is_off, shift_start, shift_end, window_start, window_end,
       actual_in, actual_out, computed_in, computed_out, transaction_count,
       is_holiday, holiday_name,
       case when is_vacation_record = 'Y' or is_mission = 'Y' or is_training = 'Y' then 'Y' else 'N' end as is_vacation,
       is_mission, is_training, is_company_permission, personal_permission_hours,
       special_leave_name, standard_hours, early_hours, late_hours,
       round(overtime_daytime_hours, 2) as before_07_hours,
       round(greatest(0, overtime_total_hours - overtime_daytime_hours), 2) as after_19_hours,
       case when rest_hours > 0 then rest_hours else cast(null as number) end as rest_hours,
       calculated_hours, is_absent, calculation_status,
       case when approved_overtime_remark is not null
            then base_remark || case when base_remark is not null then '/' end || approved_overtime_remark
            else base_remark end as remarks,
       permission_remark, approved_overtime_remark
  from final_rows
]';
end GET_EMPLOYEE_TIMESHEET;
/
