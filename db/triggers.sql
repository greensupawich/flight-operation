-- =====================================================================
--  Flight Operation · triggers.sql
--  1) สร้าง profile อัตโนมัติเมื่อมีคนล็อกอินครั้งแรก
--  2) กระจายข้อมูลรายงานหลังบิน → ชม.ลูกเรือ / ชม.เครื่อง อัตโนมัติ
--  รันหลัง policies.sql
-- =====================================================================

-- ---------------------------------------------------------------------
--  (1) ผู้ใช้ใหม่: auth.users → profiles  (pending + viewer)
--      คนแรกสุดของระบบตั้งเป็น admin อัตโนมัติ (เพื่อเริ่มให้สิทธิ์คนอื่นได้)
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  is_first  boolean;
  is_admin  boolean;
begin
  select count(*) = 0 into is_first from public.profiles;
  -- อีเมลผู้ดูแลระบบที่กำหนดไว้ = admin เสมอ (หรือผู้ใช้คนแรกสุด)
  is_admin := is_first or lower(new.email) = 'green.supawich@gmail.com';

  insert into public.profiles (id, email, full_name, role, status)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    case when is_admin then 'admin'::user_role  else 'viewer'::user_role  end,
    case when is_admin then 'active'::user_status else 'pending'::user_status end
  )
  on conflict (id) do nothing;

  return new;
end $$;

drop trigger if exists trg_new_user on auth.users;
create trigger trg_new_user after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
--  (2) กระจายข้อมูลรายงานหลังบิน
--      เมื่อมี post_flight_report เข้ามา → อัปเดต:
--        • aircraft.total_hours  (+ ชม.รวมของภารกิจ)
--        • crew_hours ของลูกเรือทุกคนในภารกิจนั้น (ตามแบบเครื่อง)
--      ทำแบบ idempotent-ish: ถ้าแก้รายงาน (update) จะปรับส่วนต่างให้
-- ---------------------------------------------------------------------
create or replace function public.distribute_post_flight()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_aircraft_id uuid;
  v_type        text;
  v_delta       numeric(10,2);
begin
  -- ส่วนต่างชั่วโมง: insert = ทั้งก้อน, update = ใหม่ - เก่า
  v_delta := new.total_hours - coalesce(old.total_hours, 0);

  -- หาเครื่องและแบบเครื่องของภารกิจนี้
  select m.aircraft_id, a.type
    into v_aircraft_id, v_type
  from public.missions m
  left join public.aircraft a on a.id = m.aircraft_id
  where m.id = new.mission_id;

  v_type := coalesce(v_type, '-');

  -- 2.1 ชม.เครื่องสะสม
  if v_aircraft_id is not null then
    update public.aircraft
       set total_hours = total_hours + v_delta
     where id = v_aircraft_id;
  end if;

  -- 2.2 ชม.บินสะสมของลูกเรือทุกคนในภารกิจ (แยกตามแบบเครื่อง)
  insert into public.crew_hours (profile_id, aircraft_type, total_hours, updated_at)
  select mc.profile_id, v_type, v_delta, now()
    from public.mission_crew mc
   where mc.mission_id = new.mission_id
  on conflict (profile_id, aircraft_type)
  do update set total_hours = public.crew_hours.total_hours + excluded.total_hours,
                updated_at  = now();

  return new;
end $$;

drop trigger if exists trg_distribute_report on public.post_flight_reports;
create trigger trg_distribute_report
  after insert or update of total_hours on public.post_flight_reports
  for each row execute function public.distribute_post_flight();

-- ---------------------------------------------------------------------
--  (2b) ถ้าลบรายงานหลังบิน → หักชั่วโมงคืน (กันข้อมูลค้าง)
-- ---------------------------------------------------------------------
create or replace function public.revert_post_flight()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_aircraft_id uuid;
  v_type        text;
begin
  select m.aircraft_id, a.type into v_aircraft_id, v_type
  from public.missions m
  left join public.aircraft a on a.id = m.aircraft_id
  where m.id = old.mission_id;

  v_type := coalesce(v_type, '-');

  if v_aircraft_id is not null then
    update public.aircraft
       set total_hours = greatest(total_hours - old.total_hours, 0)
     where id = v_aircraft_id;
  end if;

  update public.crew_hours ch
     set total_hours = greatest(ch.total_hours - old.total_hours, 0),
         updated_at  = now()
   from public.mission_crew mc
  where mc.mission_id = old.mission_id
    and ch.profile_id = mc.profile_id
    and ch.aircraft_type = v_type;

  return old;
end $$;

drop trigger if exists trg_revert_report on public.post_flight_reports;
create trigger trg_revert_report
  after delete on public.post_flight_reports
  for each row execute function public.revert_post_flight();

-- =====================================================================
--  เสร็จ Phase 1 — ทดสอบได้ทันทีใน SQL Editor:
--    1. เพิ่มเครื่อง:   insert into aircraft(tail_number,type) values ('60101','EC725');
--    2. สร้างภารกิจ + ลูกเรือ + รายงานหลังบิน
--    3. ดูผลที่ crew_hours และ aircraft.total_hours ว่าถูกอัปเดตเอง
-- =====================================================================
