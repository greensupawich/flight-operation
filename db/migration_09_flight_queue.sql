-- =====================================================================
--  Flight Operation · migration_09_flight_queue.sql
--  สำหรับหน้า "คิวบิน"
--    1) ชนิดภารกิจ STBY (Standby — จัดชื่อไว้ แต่ไม่มีบินจริง)
--    2) airfields          — รหัสสนามบิน (ชื่อจุดในเส้นทาง → รหัส เช่น บน.41 → CMA)
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
insert into public.airfields (name, code) values ('บน.41', 'CMA')
on conflict (name) do nothing;

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
