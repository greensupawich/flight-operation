-- =====================================================================
--  Flight Operation · migration_17_aircraft_status.sql
--  สถานภาพเครื่องบิน: FMC (พร้อมบิน) · PMC (พร้อมบางภารกิจ) · NMC (ไม่พร้อมบิน)
--  แก้ได้เฉพาะ admin/planner (ใช้ policy p_aircraft_write เดิม = can_plan)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================
do $$ begin
  create type aircraft_status as enum ('FMC', 'PMC', 'NMC');
exception when duplicate_object then null; end $$;

alter table public.aircraft
  add column if not exists status aircraft_status not null default 'FMC',
  add column if not exists status_note text,
  add column if not exists status_updated_at timestamptz;

-- อัปเดตเวลาปรับสถานภาพอัตโนมัติ
create or replace function public.touch_aircraft_status()
returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status or new.status_note is distinct from old.status_note then
    new.status_updated_at := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_touch_aircraft_status on public.aircraft;
create trigger trg_touch_aircraft_status before update on public.aircraft
  for each row execute function public.touch_aircraft_status();
