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
