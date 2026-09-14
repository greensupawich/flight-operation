-- =====================================================================
--  Flight Operation · catchup_2026_09_14.sql
--  รวม migration ที่ยังขาด เรียงลำดับแล้ว — รันไฟล์นี้ไฟล์เดียวใน SQL Editor
--  ทุกส่วนรันซ้ำได้ปลอดภัย
--
--  ตรวจฐานข้อมูลเมื่อ 14 ก.ย. 2569 พบว่ารันแล้ว: 01, 03, 08, 10 (ไม่รวมในไฟล์นี้)
--  ไฟล์นี้รวม: 02 → 05 → 06 → 07 → 09 → 12 → 13
--  ไม่รวม 04 (ถูกแทนที่ด้วย 05/06) และ 11 (เลิกใช้แล้ว)
--
--  หลังรันเสร็จ ให้รัน import_queue_2026_09.sql ต่อ (ข้อมูลคิวบินกันยายน)
-- =====================================================================



-- #####################################################################
-- ###  migration_02_aircraft_and_cleanup.sql
-- #####################################################################
-- =====================================================================
--  Flight Operation · migration_02_aircraft_and_cleanup.sql
--   1) ใส่รายการเครื่องบินประจำการ 6 ลำ (ตายตัว — ไม่ต้องเพิ่มเองในเว็บ)
--   2) ลบคอลัมน์ ระยะทาง / เวลา / ความสูง ที่ไม่ใช้
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

-- ---------- 1) เครื่องบินประจำการ ----------
insert into public.aircraft (tail_number, type) values
  ('60301', 'ATR72-600'),
  ('60302', 'ATR72-600'),
  ('60303', 'ATR72-600'),
  ('60313', 'ATR72-500'),
  ('60315', 'ATR72-500'),
  ('60316', 'ATR72-500')
on conflict (tail_number) do nothing;

-- ---------- 2) ลบฟิลด์ที่ไม่ใช้ ----------
alter table public.missions
  drop column if exists distance,
  drop column if exists duration,
  drop column if exists altitude;

-- =====================================================================
--  ตรวจผล: select type || '/' || tail_number as ac from aircraft order by tail_number;
--  ควรได้ ATR72-600/60301, 60302, 60303, ATR72-500/60313, 60315, 60316
-- =====================================================================


-- #####################################################################
-- ###  migration_05_recompute_hours.sql
-- #####################################################################
-- =====================================================================
--  Flight Operation · migration_05_recompute_hours.sql
--
--  ปัญหาเดิม: trigger คิด ชม. แบบ "บวกส่วนต่าง" และทำงานตอนบันทึก
--  "รายงานหลังบิน" เท่านั้น → ถ้าแก้รายชื่อนักบิน/ผูกทะเบียน/เปลี่ยนเครื่อง
--  ทีหลัง ชม. จะไม่ถูกคิดใหม่ และค่าสะสมจะเพี้ยนสะสมไปเรื่อย ๆ
--
--  แก้เป็น: คำนวณใหม่ทั้งตารางจากข้อมูลจริงทุกครั้งที่มีอะไรเปลี่ยน
--  (ข้อมูลระดับ 2-4 ภารกิจ/วัน คำนวณใหม่ทั้งหมดเร็วมาก และไม่มีทางเพี้ยน)
--
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

-- ---------- 1) ฟังก์ชันคำนวณใหม่ทั้งหมด ----------
create or replace function public.recompute_all_hours()
returns void language plpgsql security definer set search_path = public as $$
begin
  -- ===== ชม.บินรายคน: เฉพาะ IP / P / CP ที่ผูกทะเบียนนักบินไว้ =====
  delete from public.crew_hours;

  insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
  select s.crew_member_id, s.ac_type, sum(s.total_hours), now()
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
  group by s.crew_member_id, s.ac_type;

  -- ===== ชม.เครื่อง: รวมจากรายงานทั้งหมดของเครื่องลำนั้น =====
  update public.aircraft a
     set total_hours = coalesce(x.h, 0)
    from (
      select m.aircraft_id, sum(r.total_hours) as h
        from public.post_flight_reports r
        join public.missions m on m.id = r.mission_id
       where m.aircraft_id is not null
       group by m.aircraft_id
    ) x
   where a.id = x.aircraft_id;

  -- เครื่องที่ไม่มีรายงานเลย → 0
  update public.aircraft a
     set total_hours = 0
   where not exists (
     select 1 from public.post_flight_reports r
       join public.missions m on m.id = r.mission_id
      where m.aircraft_id = a.id);
end $$;

-- ---------- 2) trigger เรียกคำนวณใหม่ (statement-level = เรียกครั้งเดียวต่อคำสั่ง) ----------
create or replace function public.trg_recompute_hours()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.recompute_all_hours();
  return null;
end $$;

-- ลบ trigger แบบเก่า (บวกส่วนต่าง) ออก กันคิดซ้ำซ้อน
drop trigger if exists trg_distribute_report on public.post_flight_reports;
drop trigger if exists trg_revert_report     on public.post_flight_reports;

-- รายงานหลังบินเปลี่ยน
drop trigger if exists trg_rc_reports on public.post_flight_reports;
create trigger trg_rc_reports
  after insert or update or delete on public.post_flight_reports
  for each statement execute function public.trg_recompute_hours();

-- รายชื่อลูกเรือในภารกิจเปลี่ยน (เพิ่ม/ลบ/เปลี่ยนตำแหน่ง/ผูกทะเบียน)
drop trigger if exists trg_rc_crew on public.mission_crew;
create trigger trg_rc_crew
  after insert or update or delete on public.mission_crew
  for each statement execute function public.trg_recompute_hours();

-- เปลี่ยนเครื่องของภารกิจ
drop trigger if exists trg_rc_missions on public.missions;
create trigger trg_rc_missions
  after update of aircraft_id on public.missions
  for each statement execute function public.trg_recompute_hours();

-- ---------- 3) คำนวณใหม่ทันที 1 ครั้ง ----------
select public.recompute_all_hours();

-- =====================================================================
--  4) ตรวจสอบ: ไล่ดูทั้งสายว่าขาดตรงไหน
--     ดูคอลัมน์ "สถานะ" — ถ้าไม่ใช่ "OK นับ ชม." แปลว่าตรงนั้นคือจุดที่ขาด
-- =====================================================================
select
  m.mission_date                                as "วันที่",
  m.mission_name                                as "ภารกิจ",
  coalesce(a.type || '/' || a.tail_number, '— ไม่ได้เลือกเครื่อง —') as "เครื่อง",
  r.total_hours                                 as "ชม.ในรายงาน",
  upper(btrim(mc.position))                     as "ตำแหน่ง",
  mc.crew_name                                  as "ชื่อที่กรอก",
  c.code                                        as "รหัสทะเบียน",
  case
    when r.id is null                  then 'ยังไม่ได้บันทึกรายงานหลังบิน'
    when mc.id is null                 then 'ยังไม่ได้ใส่รายชื่อลูกเรือ'
    when upper(btrim(mc.position)) in ('AC','N')            then 'ไม่นับ (AC/N ตามระเบียบ)'
    when upper(btrim(mc.position)) not in ('IP','P','CP')   then 'ไม่นับ (ไม่ใช่ตำแหน่งนักบินที่นับ ชม.)'
    when mc.crew_member_id is null     then '>>> ไม่ได้ผูกทะเบียนนักบิน — ชม.จึงไม่เข้า <<<'
    when r.total_hours is null or r.total_hours = 0 then 'ชม.ในรายงานเป็น 0'
    else 'OK นับ ชม.'
  end                                           as "สถานะ"
from public.missions m
left join public.aircraft a            on a.id  = m.aircraft_id
left join public.post_flight_reports r on r.mission_id = m.id
left join public.mission_crew mc       on mc.mission_id = m.id
left join public.crew_members c        on c.id  = mc.crew_member_id
order by m.mission_date desc, m.mission_name, upper(btrim(mc.position));


-- #####################################################################
-- ###  migration_06_fix_delete_where.sql
-- #####################################################################
-- =====================================================================
--  Flight Operation · migration_06_fix_delete_where.sql
--
--  แก้บั๊ก: "บันทึกไม่สำเร็จ: DELETE requires a WHERE clause"
--
--  สาเหตุ: Supabase เปิดส่วนขยาย pg-safeupdate สำหรับ role ที่เรียกผ่าน API
--  ซึ่ง "ห้าม DELETE/UPDATE ที่ไม่มี WHERE" เพื่อกันลบข้อมูลยกตารางโดยพลาด
--  ฟังก์ชัน recompute_all_hours() ใช้ `delete from crew_hours;` แบบไม่มี WHERE
--  → รันใน SQL Editor ผ่าน (สิทธิ์ postgres) แต่พอ trigger ทำงานจากหน้าเว็บถูกบล็อก
--  → บันทึกภารกิจไม่ได้
--
--  วิธีแก้: ใส่ WHERE ที่ครอบทุกแถวจริง (id เป็น primary key จึงไม่มีวันเป็น null)
--
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

create or replace function public.recompute_all_hours()
returns void language plpgsql security definer set search_path = public as $$
begin
  -- ===== ชม.บินรายคน: เฉพาะ IP / P / CP ที่ผูกทะเบียนนักบินไว้ =====
  delete from public.crew_hours where id is not null;   -- WHERE ที่ครอบทุกแถว (กัน pg-safeupdate)

  insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
  select s.crew_member_id, s.ac_type, sum(s.total_hours), now()
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
  group by s.crew_member_id, s.ac_type;

  -- ===== ชม.เครื่อง: รวมจากรายงานทั้งหมดของเครื่องลำนั้น =====
  update public.aircraft a
     set total_hours = coalesce(x.h, 0)
    from (
      select m.aircraft_id, sum(r.total_hours) as h
        from public.post_flight_reports r
        join public.missions m on m.id = r.mission_id
       where m.aircraft_id is not null
       group by m.aircraft_id
    ) x
   where a.id = x.aircraft_id;

  -- เครื่องที่ไม่มีรายงานเลย → 0
  update public.aircraft a
     set total_hours = 0
   where not exists (
     select 1 from public.post_flight_reports r
       join public.missions m on m.id = r.mission_id
      where m.aircraft_id = a.id);
end $$;

-- คำนวณใหม่ 1 ครั้งให้ข้อมูลตรง
select public.recompute_all_hours();

-- =====================================================================
--  ตรวจผล: ควรบันทึกภารกิจจากหน้าเว็บได้แล้ว และ ชม.รายคนขึ้นตามนักบินที่ผูก ✓
--    select c.code, c.full_name, ch.aircraft_type, ch.total_hours
--      from crew_hours ch join crew_members c on c.id = ch.crew_member_id
--     order by ch.total_hours desc;
-- =====================================================================


-- #####################################################################
-- ###  migration_07_mission_kinds.sql
-- #####################################################################
-- =====================================================================
--  Flight Operation · migration_07_mission_kinds.sql
--  ชนิดภารกิจตามกระดานจัดบินจริง (5 ชนิด):
--    fcf        = F.C.F
--    dechochai  = เดโชชัย
--    palace     = ภารกิจสำนักพระราชวัง
--    rtaf       = ภารกิจ ทอ.
--    training   = ฝึกบิน
--  เปลี่ยนคอลัมน์จาก enum → text + check (เพิ่ม/ลดชนิดภายหลังได้ง่ายกว่า enum)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

alter table public.missions alter column kind drop default;
alter table public.missions alter column kind type text using kind::text;

-- ชนิดเดิมที่ไม่มีในชุดใหม่ (กห. / อื่นๆ) → ภารกิจ ทอ.  (แก้รายภารกิจได้ในหน้าเว็บ)
update public.missions
   set kind = 'rtaf'
 where kind is null
    or kind not in ('fcf', 'dechochai', 'palace', 'rtaf', 'training');

alter table public.missions alter column kind set default 'rtaf';
alter table public.missions alter column kind set not null;

alter table public.missions drop constraint if exists missions_kind_check;
alter table public.missions add constraint missions_kind_check
  check (kind in ('fcf', 'dechochai', 'palace', 'rtaf', 'training'));

drop type if exists mission_kind;


-- #####################################################################
-- ###  migration_09_flight_queue.sql
-- #####################################################################
-- =====================================================================
--  Flight Operation · migration_09_flight_queue.sql
--  สำหรับหน้า "คิวบิน"
--    1) ชนิดภารกิจ STBY (Standby — จัดชื่อไว้ แต่ไม่มีบินจริง)
--    2) airfields          — รหัสสนามบิน (ชื่อจุดในเส้นทาง → รหัส เช่น บน.41 → CNX)
--    3) holidays           — วันหยุดราชการ (เสาร์-อาทิตย์ระบบทำสีเทาให้เองอยู่แล้ว)
--    4) crew_unavailable   — วันที่นักบินไม่ว่าง (ช่องสีแดง)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

-- ---------- 1) STBY ----------
alter table public.missions drop constraint if exists missions_kind_check;
alter table public.missions add constraint missions_kind_check
  check (kind in ('fcf', 'dechochai', 'palace', 'rtaf', 'training', 'stby'));

-- ---------- 2) รหัสสนามบิน ----------
-- name เก็บแบบตัดช่องว่างออกทั้งหมด เช่น "บน.41"
create table if not exists public.airfields (
  name        text primary key,
  code        text not null,
  updated_at  timestamptz not null default now()
);
-- บน.41 = CNX (ถ้าเคยรันไฟล์รุ่นก่อนที่ใส่ CMA ไว้ จะแก้เป็น CNX ให้)
insert into public.airfields (name, code) values ('บน.41', 'CNX')
on conflict (name) do update set code = 'CNX', updated_at = now()
  where public.airfields.code = 'CMA';

alter table public.airfields enable row level security;
drop policy if exists p_airfields_read on public.airfields;
create policy p_airfields_read on public.airfields for select using ( public.is_active() );
drop policy if exists p_airfields_write on public.airfields;
create policy p_airfields_write on public.airfields for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- ---------- 3) วันหยุดราชการ ----------
create table if not exists public.holidays (
  holiday_date  date primary key,
  name          text
);
alter table public.holidays enable row level security;
drop policy if exists p_holidays_read on public.holidays;
create policy p_holidays_read on public.holidays for select using ( public.is_active() );
drop policy if exists p_holidays_write on public.holidays;
create policy p_holidays_write on public.holidays for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- ---------- 4) วันไม่ว่างของนักบิน ----------
create table if not exists public.crew_unavailable (
  crew_member_id  uuid not null references public.crew_members(id) on delete cascade,
  off_date        date not null,
  note            text,
  created_at      timestamptz not null default now(),
  primary key (crew_member_id, off_date)
);
create index if not exists idx_crew_unavailable_date on public.crew_unavailable(off_date);

alter table public.crew_unavailable enable row level security;
drop policy if exists p_unavail_read on public.crew_unavailable;
create policy p_unavail_read on public.crew_unavailable for select using ( public.is_active() );
drop policy if exists p_unavail_write on public.crew_unavailable;
create policy p_unavail_write on public.crew_unavailable for all
  using ( public.can_plan() ) with check ( public.can_plan() );


-- #####################################################################
-- ###  migration_12_queue_entries.sql
-- #####################################################################
-- =====================================================================
--  Flight Operation · migration_12_queue_entries.sql
--  ช่องในหน้าคิวบินที่ผู้วางแผน/admin พิมพ์แก้เองได้ (แบบ Excel)
--   • 1 ช่อง (นักบิน × วัน) = 1 รายการ
--   • code    : ข้อความในช่อง เช่น CNX / ST / LB (ว่างได้ = สีอย่างเดียว)
--   • kind    : สีชนิดภารกิจ
--   • ac_type : '600' ตัวดำ / '500' ตัวแดง
--   ถ้าช่องมีรายการนี้ จะแสดงแทนข้อมูลที่คำนวณจากภารกิจในช่องนั้น
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================
create table if not exists public.queue_entries (
  id              uuid primary key default gen_random_uuid(),
  crew_member_id  uuid not null references public.crew_members(id) on delete cascade,
  entry_date      date not null,
  code            text,
  kind            text not null default 'rtaf'
                  check (kind in ('fcf','dechochai','palace','rtaf','training','stby')),
  ac_type         text check (ac_type in ('600','500')),
  updated_by      uuid references public.profiles(id) on delete set null,
  updated_at      timestamptz not null default now(),
  unique (crew_member_id, entry_date)
);
create index if not exists idx_queue_entries_date on public.queue_entries(entry_date);

alter table public.queue_entries enable row level security;
drop policy if exists p_qe_read on public.queue_entries;
create policy p_qe_read on public.queue_entries for select using ( public.is_active() );
drop policy if exists p_qe_write on public.queue_entries;
create policy p_qe_write on public.queue_entries for all
  using ( public.can_plan() ) with check ( public.can_plan() );


-- #####################################################################
-- ###  migration_13_open_availability.sql
-- #####################################################################
-- =====================================================================
--  Flight Operation · migration_13_open_availability.sql
--  หน้าวัน: ผู้ใช้ที่ได้รับอนุมัติทุกคน เพิ่ม/ลบ "นักบินที่ไม่ว่าง" ของนักบินคนไหนก็ได้
--  (เดิมแก้ได้เฉพาะของตัวเอง) · เก็บว่าใครเป็นคนเพิ่มไว้ใน created_by
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================
alter table public.crew_unavailable
  add column if not exists created_by uuid references public.profiles(id) on delete set null
  default auth.uid();

drop policy if exists p_unavail_self_ins on public.crew_unavailable;
drop policy if exists p_unavail_self_upd on public.crew_unavailable;
drop policy if exists p_unavail_self_del on public.crew_unavailable;

drop policy if exists p_unavail_active_write on public.crew_unavailable;
create policy p_unavail_active_write on public.crew_unavailable for all
  using ( public.is_active() ) with check ( public.is_active() );


-- =====================================================================
--  ตรวจผลรวม: ทุกแถวควรเป็น true
-- =====================================================================
select
  to_regclass('public.airfields')        is not null as "airfields",
  to_regclass('public.holidays')         is not null as "holidays",
  to_regclass('public.crew_unavailable') is not null as "crew_unavailable",
  to_regclass('public.queue_entries')    is not null as "queue_entries",
  not exists (select 1 from information_schema.columns
               where table_schema='public' and table_name='missions' and column_name='distance') as "ลบคอลัมน์ระยะทางแล้ว",
  (select count(*) from public.aircraft where tail_number in ('60301','60302','60303','60313','60315','60316')) = 6 as "เครื่อง 6 ลำ",
  exists (select 1 from pg_trigger where tgname = 'trg_rc_crew') as "trigger คิด ชม.ใหม่";
