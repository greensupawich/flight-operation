-- =====================================================================
--  Flight Operation · migration_25_archive.sql
--  เคลียร์ข้อมูลดิบรายเดือน (เก็บ 3 เดือนล่าสุด + เดือนปัจจุบัน) โดยไม่ให้ยอดสรุปหาย
--
--  หลักการ
--   • ข้อมูลดิบ  = ภารกิจ + ลูกเรือ + ขาการบิน + รายงานหลังบิน + รายงานอันตราย + ไฟล์แนบ
--                 + ข้อขัดข้อง + น.จัดบิน (day_notes) + ช่องคิวบิน + วันไม่ว่าง
--     → export เป็นไฟล์รายเดือน (หน้า archive.html) แล้วจึงลบออกจากฐานข้อมูลได้
--   • ข้อมูลสรุป = เก็บต่อในฐานข้อมูล (ส่งต่อทุกเดือน)
--       - ชม.บินสะสมรายคน / รายเครื่อง  → "ยอดยกมา" crew_hours_carry / aircraft.hours_carry
--         (recompute_all_hours = ยอดยกมา + รายงานที่ยังเหลืออยู่ → ยอดไม่เปลี่ยนหลังเคลียร์)
--       - สถิติรายวันแยกประเภท           → stats_daily        (หน้า สถิติ)
--       - สถิติรายเดือนรายคน              → stats_crew_monthly (หน้า ทะเบียนนักบิน)
--       - สถิติรายเดือนรายเครื่อง          → stats_aircraft_monthly
--       - สถานภาพเครื่อง / ประวัติสถานภาพ / currency 500-600 / ทะเบียน → ไม่ถูกลบ
--   • เคลียร์ได้เฉพาะ admin/planner · ต้อง export เดือนนั้นก่อน (archive_log.exported_at)
--   • เดือนที่เคลียร์ได้ = เก่ากว่า 3 เดือนเต็มล่าสุด (ต.ค. → เก็บ ก.ค.–ต.ค. · เคลียร์ได้ถึง มิ.ย.)
--
--  ต้องรัน migration_24 มาก่อน · รันซ้ำได้ ปลอดภัย
-- =====================================================================

-- ---------- 1) ยอดยกมา ----------
alter table public.aircraft add column if not exists hours_carry numeric(10,2) not null default 0;

create table if not exists public.crew_hours_carry (
  crew_member_id  uuid not null references public.crew_members(id) on delete cascade,
  aircraft_type   text not null,
  hours           numeric(10,2) not null default 0,
  updated_at      timestamptz not null default now(),
  primary key (crew_member_id, aircraft_type)
);

-- ---------- 2) สถิติสรุป ----------
create table if not exists public.stats_daily (
  stat_date  date not null,
  kind       text not null,
  flights    int not null default 0,
  hours      numeric(10,2) not null default 0,
  primary key (stat_date, kind)
);

create table if not exists public.stats_crew_monthly (
  ym              date not null,              -- วันที่ 1 ของเดือน
  crew_member_id  uuid not null references public.crew_members(id) on delete cascade,
  flights         int not null default 0,
  hours           numeric(10,2) not null default 0,
  last_flight     date,
  primary key (ym, crew_member_id)
);

create table if not exists public.stats_aircraft_monthly (
  ym              date not null,
  aircraft_id     uuid not null references public.aircraft(id) on delete cascade,
  flights         int not null default 0,
  hours           numeric(10,2) not null default 0,
  discrepancies   int not null default 0,
  safety_reports  int not null default 0,
  primary key (ym, aircraft_id)
);

create table if not exists public.archive_log (
  ym             date primary key,
  exported_at    timestamptz,
  exported_by    uuid,
  export_counts  jsonb,
  purged_at      timestamptz,
  purged_by      uuid,
  purge_counts   jsonb
);

-- อ่านได้ทุกคนที่ active · เขียนผ่านฟังก์ชันด้านล่างเท่านั้น (security definer)
do $$ declare t text; begin
  foreach t in array array['crew_hours_carry','stats_daily','stats_crew_monthly',
                           'stats_aircraft_monthly','archive_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists p_%s_read on public.%I', t, t);
    execute format('create policy p_%s_read on public.%I for select using ( public.is_active() )', t, t);
  end loop;
end $$;

-- ---------- 3) คำนวณ ชม.สะสมใหม่ = ยอดยกมา + รายงานที่เหลือ ----------
--  (ตรรกะเดิมจาก migration_06 ทุกอย่าง แค่บวกยอดยกมาเพิ่ม)
create or replace function public.recompute_all_hours()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.crew_hours where id is not null;   -- WHERE ครอบทุกแถว (กัน pg-safeupdate)

  insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
  select k.crew_member_id, k.ac_type, sum(k.h), now()
  from (
    select s.crew_member_id, s.ac_type, s.total_hours as h
    from (
      select distinct m.id as mission_id, mc.crew_member_id,
             coalesce(a.type, '-') as ac_type, r.total_hours
        from public.post_flight_reports r
        join public.missions m      on m.id = r.mission_id
        left join public.aircraft a on a.id = m.aircraft_id
        join public.mission_crew mc on mc.mission_id = m.id
       where mc.crew_member_id is not null
         and coalesce(upper(btrim(mc.position)), '') in ('IP', 'P', 'CP')
    ) s
    union all
    select c.crew_member_id, c.aircraft_type, c.hours
      from public.crew_hours_carry c
     where c.hours <> 0
  ) k
  group by k.crew_member_id, k.ac_type;

  update public.aircraft a
     set total_hours = a.hours_carry + coalesce((
           select sum(r.total_hours)
             from public.post_flight_reports r
             join public.missions m on m.id = r.mission_id
            where m.aircraft_id = a.id), 0)
   where a.id is not null;
end $$;

-- ---------- 4) บันทึกว่า export เดือนนี้แล้ว (เรียกจากหน้าเว็บหลังดาวน์โหลดไฟล์) ----------
create or replace function public.archive_mark_exported(p_ym date, p_counts jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_ym date := date_trunc('month', p_ym)::date;
begin
  if not public.can_plan() then raise exception 'เฉพาะผู้วางแผน/ผู้ดูแลระบบ'; end if;
  insert into public.archive_log (ym, exported_at, exported_by, export_counts)
  values (v_ym, now(), auth.uid(), p_counts)
  on conflict (ym) do update
    set exported_at = excluded.exported_at, exported_by = excluded.exported_by,
        export_counts = excluded.export_counts;
end $$;

-- ---------- 5) เคลียร์ข้อมูลดิบ 1 เดือน ----------
--  ไฟล์รูป/วีดีโอใน Storage หน้าเว็บลบให้ก่อนเรียกฟังก์ชันนี้ (SQL ลบไฟล์ใน Storage ตรง ๆ ไม่ได้)
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
  insert into public.stats_daily (stat_date, kind, flights, hours)
  select m.mission_date, m.kind, count(*), coalesce(sum(r.total_hours), 0)
    from _pm m join public.post_flight_reports r on r.mission_id = m.id
   group by m.mission_date, m.kind
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
revoke all on function public.archive_mark_exported(date, jsonb) from public, anon;
grant execute on function public.archive_mark_exported(date, jsonb) to authenticated;

-- คำนวณใหม่ 1 ครั้ง (ยังไม่มียอดยกมา → ผลเท่าเดิม)
select public.recompute_all_hours();
