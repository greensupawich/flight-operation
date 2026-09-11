-- =====================================================================
--  Flight Operation · schema.sql
--  โครงสร้างตารางทั้งหมด (PostgreSQL / Supabase)
--  รันครั้งเดียวใน Supabase → SQL Editor
--  ลำดับการรัน: 1) schema.sql  2) policies.sql  3) triggers.sql
-- =====================================================================

-- ---------- ENUM: บทบาท / สถานะผู้ใช้ ----------
do $$ begin
  create type user_role   as enum ('admin','planner','pilot','crew','viewer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type user_status as enum ('pending','active','disabled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type mission_status as enum ('planned','flying','completed','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type discrepancy_status as enum ('open','in_progress','resolved');
exception when duplicate_object then null; end $$;

-- =====================================================================
--  1) profiles — ผู้ใช้ทุกคน (เชื่อมกับ auth.users ของ Supabase)
-- =====================================================================
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text unique not null,
  full_name   text,
  rank        text,                              -- ยศ/ตำแหน่ง
  role        user_role   not null default 'viewer',
  status      user_status not null default 'pending',
  created_at  timestamptz not null default now()
);

-- =====================================================================
--  2) aircraft — ทะเบียนเครื่องบิน  (total_hours อัปเดตอัตโนมัติ)
-- =====================================================================
create table if not exists public.aircraft (
  id           uuid primary key default gen_random_uuid(),
  tail_number  text unique not null,             -- ทะเบียนเครื่อง เช่น 60101
  type         text,                             -- แบบเครื่อง
  total_hours  numeric(10,2) not null default 0, -- ชม.สะสม (trigger อัปเดต)
  created_at   timestamptz not null default now()
);

-- =====================================================================
--  3) missions — ภารกิจรายวัน (2–4 ต่อวัน)
-- =====================================================================
create table if not exists public.missions (
  id            uuid primary key default gen_random_uuid(),
  mission_date  date not null,
  mission_name  text not null,
  aircraft_id   uuid references public.aircraft(id) on delete set null,
  route         text,                            -- เส้นทางบิน
  planned_time  text,                            -- เวลาที่วางแผน (เช่น 08:00-10:00)
  status        mission_status not null default 'planned',
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_missions_date on public.missions(mission_date);

-- =====================================================================
--  4) mission_crew — ใครบินภารกิจไหน (~10 คน/ไฟลท์)
-- =====================================================================
create table if not exists public.mission_crew (
  id          uuid primary key default gen_random_uuid(),
  mission_id  uuid not null references public.missions(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  position    text,                              -- นักบิน / เจ้าหน้าที่ / ฯลฯ
  unique (mission_id, profile_id)
);
create index if not exists idx_crew_mission on public.mission_crew(mission_id);
create index if not exists idx_crew_profile on public.mission_crew(profile_id);

-- =====================================================================
--  5) flight_legs — แต่ละขาที่บิน
-- =====================================================================
create table if not exists public.flight_legs (
  id          uuid primary key default gen_random_uuid(),
  mission_id  uuid not null references public.missions(id) on delete cascade,
  leg_no      int,
  from_point  text,
  to_point    text,
  hours       numeric(6,2) not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists idx_legs_mission on public.flight_legs(mission_id);

-- =====================================================================
--  6) post_flight_reports — รายงานหลังบิน (จุดกรอกข้อมูลครั้งเดียว)
-- =====================================================================
create table if not exists public.post_flight_reports (
  id           uuid primary key default gen_random_uuid(),
  mission_id   uuid not null references public.missions(id) on delete cascade,
  total_hours  numeric(6,2) not null default 0,  -- ชม.บินรวมของภารกิจ
  remarks      text,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (mission_id)                            -- 1 ภารกิจ = 1 รายงาน
);

-- =====================================================================
--  7) crew_hours — ชม.บินสะสมรายคน  (trigger อัปเดตอัตโนมัติ)
-- =====================================================================
create table if not exists public.crew_hours (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  aircraft_type  text not null default '-',
  total_hours    numeric(10,2) not null default 0,
  updated_at     timestamptz not null default now(),
  unique (profile_id, aircraft_type)
);
create index if not exists idx_crewhours_profile on public.crew_hours(profile_id);

-- =====================================================================
--  8) discrepancies — ข้อขัดข้อง → ผูกกับเครื่อง (trigger เพิ่มให้ได้)
-- =====================================================================
create table if not exists public.discrepancies (
  id            uuid primary key default gen_random_uuid(),
  aircraft_id   uuid references public.aircraft(id) on delete set null,
  mission_id    uuid references public.missions(id) on delete set null,
  description   text not null,
  status        discrepancy_status not null default 'open',
  reported_date date not null default current_date,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_disc_aircraft on public.discrepancies(aircraft_id);

-- =====================================================================
--  หมายเหตุ: หลังรันไฟล์นี้ ให้รัน policies.sql แล้วตามด้วย triggers.sql
-- =====================================================================
