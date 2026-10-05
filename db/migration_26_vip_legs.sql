-- =====================================================================
--  Flight Operation · migration_26_vip_legs.sql
--  ภารกิจสำนักพระราชวัง / เดโชชัย: ติ๊ก "คณะวัง" รายขาในรายงานหลังบิน
--   • flight_legs.vip = ขานี้มีคณะวังอยู่บนเครื่อง
--   • หน้า สถิติ: ชม.ขาที่ติ๊ก → ประเภทภารกิจ (วัง/เดโชชัย) · ชม.ที่เหลือ → ฝึกบิน
--     จำนวนเที่ยวยังนับในประเภทภารกิจ · ภารกิจที่ไม่มีขาไหนติ๊กเลย = นับทั้งหมดเป็นประเภทเดิม
--   • archive_purge_month เก็บสถิติสรุปตามกฎเดียวกัน
--  ต้องรัน migration_25 มาก่อน · รันซ้ำได้ ปลอดภัย
-- =====================================================================
alter table public.flight_legs add column if not exists vip boolean not null default false;

-- ชม.ขาที่มีคณะวัง ของภารกิจ (เฉพาะประเภท palace / dechochai)
create or replace function public.mission_vip_hours(p_mission uuid, p_kind text)
returns table (any_vip boolean, vip_h numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(bool_or(l.vip), false) and p_kind in ('palace', 'dechochai'),
         coalesce(sum(l.hours) filter (where l.vip), 0)
    from public.flight_legs l
   where l.mission_id = p_mission;
$$;

create or replace function public.archive_purge_month(p_ym date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_start   date := date_trunc('month', p_ym)::date;
  v_end     date := (date_trunc('month', p_ym) + interval '1 month')::date;
  v_limit   date := (date_trunc('month', current_date) - interval '4 months')::date;  -- เก็บ 3 เดือนเต็ม + เดือนปัจจุบัน
  v_counts  jsonb;
  n_m int; n_d int; n_s int; n_r int; n_med int; n_notes int; n_q int; n_u int;
begin
  if not public.can_plan() then raise exception 'เฉพาะผู้วางแผน/ผู้ดูแลระบบ'; end if;
  if v_start > v_limit then
    raise exception 'ต้องเก็บข้อมูล 3 เดือนล่าสุดไว้ — เดือนนี้ยังเคลียร์ไม่ได้ (เคลียร์ได้ถึง %)', to_char(v_limit, 'YYYY-MM');
  end if;
  if not exists (select 1 from public.archive_log where ym = v_start and exported_at is not null) then
    raise exception 'ยังไม่ได้ export เดือน % — ต้อง export ก่อนจึงเคลียร์ได้', to_char(v_start, 'YYYY-MM');
  end if;

  -- ภารกิจของเดือน
  create temp table _pm on commit drop as
    select id, aircraft_id, mission_date, status, coalesce(kind::text, 'rtaf') as kind
      from public.missions where mission_date >= v_start and mission_date < v_end;

  -- (ก) สถิติรายวันแยกประเภท — ตรงกับ stats.html (นับทุกรายงาน)
  --     ภารกิจวัง/เดโชชัยที่ติ๊ก "คณะวัง" ไว้ (migration_26): ชม.ขาที่ติ๊ก → ประเภทภารกิจ · ส่วนที่เหลือ → ฝึกบิน
  --     (เที่ยวนับในประเภทภารกิจเท่านั้น · ไม่มีขาไหนติ๊กเลย = ทั้งภารกิจเป็นประเภทเดิม)
  insert into public.stats_daily (stat_date, kind, flights, hours)
  select x.d, x.k, sum(x.f), coalesce(sum(x.h), 0)
    from (
      select m.mission_date as d, m.kind as k, 1 as f,
             case when v.any_vip then v.vip_h else r.total_hours end as h
        from _pm m
        join public.post_flight_reports r on r.mission_id = m.id
        cross join lateral public.mission_vip_hours(m.id, m.kind) v
      union all
      select m.mission_date, 'training', 0, greatest(r.total_hours - v.vip_h, 0)
        from _pm m
        join public.post_flight_reports r on r.mission_id = m.id
        cross join lateral public.mission_vip_hours(m.id, m.kind) v
       where v.any_vip and r.total_hours > v.vip_h
    ) x
   group by x.d, x.k
  on conflict (stat_date, kind) do update
    set flights = public.stats_daily.flights + excluded.flights,
        hours   = public.stats_daily.hours   + excluded.hours;

  -- (ข) สถิติรายเดือนรายคน — ตรงกับ crew.js loadMonthlyStats
  --     เที่ยว = ทุกตำแหน่งนักบิน (AC/IP/P/CP/N) · ชม. = เฉพาะ IP/P/CP · ไม่นับภารกิจยกเลิก
  insert into public.stats_crew_monthly (ym, crew_member_id, flights, hours, last_flight)
  select v_start, x.crew_member_id, count(*), coalesce(sum(case when x.counts_hours then x.h end), 0), max(x.d)
    from (
      select mc.crew_member_id, m.id, m.mission_date as d, r.total_hours as h,
             bool_or(upper(btrim(coalesce(mc.position, ''))) in ('IP','P','CP')) as counts_hours
        from _pm m
        join public.post_flight_reports r on r.mission_id = m.id
        join public.mission_crew mc on mc.mission_id = m.id
       where mc.crew_member_id is not null
         and m.status is distinct from 'cancelled'
         and upper(btrim(coalesce(mc.position, ''))) in ('AC','IP','P','CP','N')
       group by mc.crew_member_id, m.id, m.mission_date, r.total_hours
    ) x
   group by x.crew_member_id
  on conflict (ym, crew_member_id) do update
    set flights     = public.stats_crew_monthly.flights + excluded.flights,
        hours       = public.stats_crew_monthly.hours   + excluded.hours,
        last_flight = greatest(public.stats_crew_monthly.last_flight, excluded.last_flight);

  -- (ค) สถิติรายเดือนรายเครื่อง
  insert into public.stats_aircraft_monthly (ym, aircraft_id, flights, hours, discrepancies, safety_reports)
  select v_start, a.id,
         (select count(*) from _pm m join public.post_flight_reports r on r.mission_id = m.id where m.aircraft_id = a.id),
         (select coalesce(sum(r.total_hours), 0) from _pm m join public.post_flight_reports r on r.mission_id = m.id where m.aircraft_id = a.id),
         (select count(*) from public.discrepancies d
           where d.aircraft_id = a.id
             and ((d.reported_date >= v_start and d.reported_date < v_end) or d.mission_id in (select id from _pm))),
         (select count(*) from _pm m join public.safety_reports s on s.mission_id = m.id where m.aircraft_id = a.id)
    from public.aircraft a
  on conflict (ym, aircraft_id) do update
    set flights        = public.stats_aircraft_monthly.flights        + excluded.flights,
        hours          = public.stats_aircraft_monthly.hours          + excluded.hours,
        discrepancies  = public.stats_aircraft_monthly.discrepancies  + excluded.discrepancies,
        safety_reports = public.stats_aircraft_monthly.safety_reports + excluded.safety_reports;
  delete from public.stats_aircraft_monthly
   where ym = v_start and flights = 0 and discrepancies = 0 and safety_reports = 0;

  -- (ง) ยอด ชม.สะสม ก่อนลบ (คำนวณให้ตรงก่อน แล้วจดไว้)
  perform public.recompute_all_hours();
  create temp table _ch_before on commit drop as
    select crew_member_id, aircraft_type, total_hours from public.crew_hours where crew_member_id is not null;
  create temp table _ac_before on commit drop as
    select id, total_hours from public.aircraft;

  -- (จ) ลบข้อมูลดิบ
  select count(*) into n_r   from _pm m join public.post_flight_reports r on r.mission_id = m.id;
  select count(*) into n_s   from _pm m join public.safety_reports s on s.mission_id = m.id;
  select count(*) into n_med from _pm m join public.report_media x on x.mission_id = m.id;

  delete from public.discrepancies d
   where (d.reported_date >= v_start and d.reported_date < v_end)
      or d.mission_id in (select id from _pm);
  get diagnostics n_d = row_count;

  delete from public.missions where id in (select id from _pm);   -- cascade: crew/legs/reports/safety/media
  get diagnostics n_m = row_count;

  delete from public.day_notes        where log_date   >= v_start and log_date   < v_end;
  get diagnostics n_notes = row_count;
  delete from public.queue_entries    where entry_date >= v_start and entry_date < v_end;
  get diagnostics n_q = row_count;
  delete from public.crew_unavailable where off_date   >= v_start and off_date   < v_end;
  get diagnostics n_u = row_count;

  -- (ฉ) ส่วนที่หายไป → ย้ายเข้ายอดยกมา แล้วคำนวณใหม่ (ยอดรวมต้องเท่าเดิม)
  perform public.recompute_all_hours();

  insert into public.crew_hours_carry (crew_member_id, aircraft_type, hours, updated_at)
  select b.crew_member_id, b.aircraft_type, b.total_hours - coalesce(a.total_hours, 0), now()
    from _ch_before b
    left join public.crew_hours a
      on a.crew_member_id = b.crew_member_id and a.aircraft_type = b.aircraft_type
   where b.total_hours - coalesce(a.total_hours, 0) <> 0
  on conflict (crew_member_id, aircraft_type) do update
    set hours = public.crew_hours_carry.hours + excluded.hours, updated_at = now();

  update public.aircraft a
     set hours_carry = a.hours_carry + (b.total_hours - a.total_hours)
    from _ac_before b
   where b.id = a.id and b.total_hours <> a.total_hours;

  perform public.recompute_all_hours();

  v_counts := jsonb_build_object('missions', n_m, 'reports', n_r, 'discrepancies', n_d,
                                 'safety_reports', n_s, 'media', n_med, 'day_notes', n_notes,
                                 'queue_entries', n_q, 'unavailable', n_u);
  update public.archive_log
     set purged_at = now(), purged_by = auth.uid(), purge_counts = v_counts
   where ym = v_start;
  return v_counts;
end $$;

revoke all on function public.archive_purge_month(date) from public, anon;
grant execute on function public.archive_purge_month(date) to authenticated;
