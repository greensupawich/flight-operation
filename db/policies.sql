-- =====================================================================
--  Flight Operation · policies.sql
--  Row Level Security (RLS) — บังคับสิทธิ์ที่ระดับฐานข้อมูล
--  รันหลัง schema.sql
-- =====================================================================

-- ---------- ฟังก์ชันช่วยเช็คสิทธิ์ (security definer อ่าน profiles ได้) ----------
create or replace function public.current_role()
returns user_role language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_active()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and status = 'active');
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role = 'admin' and status = 'active');
$$;

-- can_plan = admin หรือ planner (สร้าง/แก้ภารกิจได้)
create or replace function public.can_plan()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and status = 'active'
                   and role in ('admin','planner'));
$$;

-- flies_mission = ผู้ใช้อยู่ในลูกเรือของภารกิจนั้น
create or replace function public.flies_mission(m uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.mission_crew
                 where mission_id = m and profile_id = auth.uid());
$$;

-- ---------- เปิด RLS ทุกตาราง ----------
alter table public.profiles            enable row level security;
alter table public.aircraft            enable row level security;
alter table public.missions            enable row level security;
alter table public.mission_crew        enable row level security;
alter table public.flight_legs         enable row level security;
alter table public.post_flight_reports enable row level security;
alter table public.crew_hours          enable row level security;
alter table public.discrepancies       enable row level security;

-- =====================================================================
--  profiles
-- =====================================================================
-- ทุกคนที่ล็อกอินเห็นโปรไฟล์ตัวเอง; active user เห็นทุกโปรไฟล์ (ไว้จัดลูกเรือ)
drop policy if exists p_profiles_select on public.profiles;
create policy p_profiles_select on public.profiles for select
  using ( id = auth.uid() or public.is_active() );

-- แก้ได้เฉพาะชื่อ/ยศของตัวเอง — role/status ห้ามแตะ (บังคับใน trigger ด้านล่าง)
drop policy if exists p_profiles_update_self on public.profiles;
create policy p_profiles_update_self on public.profiles for update
  using ( id = auth.uid() ) with check ( id = auth.uid() );

-- admin จัดการทุกโปรไฟล์ (ให้/เพิกถอนสิทธิ์)
drop policy if exists p_profiles_admin on public.profiles;
create policy p_profiles_admin on public.profiles for all
  using ( public.is_admin() ) with check ( public.is_admin() );

-- กันไม่ให้คนทั่วไปแก้ role/status ของตัวเอง (เฉพาะ admin เท่านั้น)
create or replace function public.guard_profile_privilege()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() then
    return new;                       -- admin แก้ได้ทุกอย่าง
  end if;
  if new.role <> old.role or new.status <> old.status then
    raise exception 'เฉพาะ admin เท่านั้นที่แก้ role/status ได้';
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_profile on public.profiles;
create trigger trg_guard_profile before update on public.profiles
  for each row execute function public.guard_profile_privilege();

-- =====================================================================
--  aircraft — active อ่านได้ / planner+admin แก้ได้
-- =====================================================================
drop policy if exists p_aircraft_read on public.aircraft;
create policy p_aircraft_read on public.aircraft for select
  using ( public.is_active() );

drop policy if exists p_aircraft_write on public.aircraft;
create policy p_aircraft_write on public.aircraft for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- =====================================================================
--  missions — active อ่านได้ / planner+admin สร้าง-แก้
-- =====================================================================
drop policy if exists p_missions_read on public.missions;
create policy p_missions_read on public.missions for select
  using ( public.is_active() );

drop policy if exists p_missions_write on public.missions;
create policy p_missions_write on public.missions for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- =====================================================================
--  mission_crew — active อ่านได้ / planner+admin จัดลูกเรือ
-- =====================================================================
drop policy if exists p_crew_read on public.mission_crew;
create policy p_crew_read on public.mission_crew for select
  using ( public.is_active() );

drop policy if exists p_crew_write on public.mission_crew;
create policy p_crew_write on public.mission_crew for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- =====================================================================
--  flight_legs — active อ่าน / คนที่บินภารกิจนั้น หรือ planner แก้ได้
-- =====================================================================
drop policy if exists p_legs_read on public.flight_legs;
create policy p_legs_read on public.flight_legs for select
  using ( public.is_active() );

drop policy if exists p_legs_write on public.flight_legs;
create policy p_legs_write on public.flight_legs for all
  using ( public.can_plan() or public.flies_mission(mission_id) )
  with check ( public.can_plan() or public.flies_mission(mission_id) );

-- =====================================================================
--  post_flight_reports — คนที่บินไฟลท์นั้น (หรือ planner) กรอกได้
-- =====================================================================
drop policy if exists p_reports_read on public.post_flight_reports;
create policy p_reports_read on public.post_flight_reports for select
  using ( public.is_active() );

drop policy if exists p_reports_write on public.post_flight_reports;
create policy p_reports_write on public.post_flight_reports for all
  using ( public.can_plan() or public.flies_mission(mission_id) )
  with check ( public.can_plan() or public.flies_mission(mission_id) );

-- =====================================================================
--  crew_hours — active อ่านได้ / เขียนผ่าน trigger (service) เท่านั้น
--  ไม่มี policy write ให้ผู้ใช้ทั่วไป = แก้มือไม่ได้ กันข้อมูลเพี้ยน
-- =====================================================================
drop policy if exists p_crewhours_read on public.crew_hours;
create policy p_crewhours_read on public.crew_hours for select
  using ( public.is_active() );

drop policy if exists p_crewhours_admin on public.crew_hours;
create policy p_crewhours_admin on public.crew_hours for all
  using ( public.is_admin() ) with check ( public.is_admin() );

-- =====================================================================
--  discrepancies — active อ่าน / คนบินไฟลท์+planner เพิ่มได้ / admin จัดการ
-- =====================================================================
drop policy if exists p_disc_read on public.discrepancies;
create policy p_disc_read on public.discrepancies for select
  using ( public.is_active() );

drop policy if exists p_disc_insert on public.discrepancies;
create policy p_disc_insert on public.discrepancies for insert
  with check ( public.can_plan() or (mission_id is not null and public.flies_mission(mission_id)) );

drop policy if exists p_disc_manage on public.discrepancies;
create policy p_disc_manage on public.discrepancies for update
  using ( public.can_plan() ) with check ( public.can_plan() );

drop policy if exists p_disc_delete on public.discrepancies;
create policy p_disc_delete on public.discrepancies for delete
  using ( public.is_admin() );

-- =====================================================================
--  รันต่อ: triggers.sql
-- =====================================================================
