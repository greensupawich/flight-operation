-- =====================================================================
--  Flight Operation · migration_19_aircraft_defects_checks.sql
--  สองส่วนใหม่ต่อเครื่อง (แก้ได้เฉพาะ admin/planner):
--   1) aircraft_defects — ข้อขัดข้องประจำเครื่อง (รายการค้างของเครื่อง ไม่ผูกภารกิจ)
--   2) aircraft_checks  — รายการเช็คตามวงรอบ (2 M / A..-Cx / C-Cx ฯลฯ) + กำหนดครบ
--  ต้องรัน migration_17 ก่อน · รันซ้ำได้ ปลอดภัย
-- =====================================================================
create table if not exists public.aircraft_defects (
  id           uuid primary key default gen_random_uuid(),
  aircraft_id  uuid not null references public.aircraft(id) on delete cascade,
  seq          int not null default 0,
  description  text not null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_ac_defects on public.aircraft_defects(aircraft_id, seq);

create table if not exists public.aircraft_checks (
  id           uuid primary key default gen_random_uuid(),
  aircraft_id  uuid not null references public.aircraft(id) on delete cascade,
  seq          int not null default 0,
  name         text not null,          -- เช่น '2 M', 'A11-Cx', 'C-Cx', 'HANGAR QUEEN'
  due_text     text,                   -- เช่น '21 - 22 ก.ย.69' (เก็บเป็นข้อความตามกระดาน)
  created_at   timestamptz not null default now()
);
create index if not exists idx_ac_checks on public.aircraft_checks(aircraft_id, seq);

alter table public.aircraft_defects enable row level security;
alter table public.aircraft_checks  enable row level security;

drop policy if exists p_acdef_read on public.aircraft_defects;
create policy p_acdef_read on public.aircraft_defects for select using ( public.is_active() );
drop policy if exists p_acdef_write on public.aircraft_defects;
create policy p_acdef_write on public.aircraft_defects for all
  using ( public.can_plan() ) with check ( public.can_plan() );

drop policy if exists p_acchk_read on public.aircraft_checks;
create policy p_acchk_read on public.aircraft_checks for select using ( public.is_active() );
drop policy if exists p_acchk_write on public.aircraft_checks;
create policy p_acchk_write on public.aircraft_checks for all
  using ( public.can_plan() ) with check ( public.can_plan() );
