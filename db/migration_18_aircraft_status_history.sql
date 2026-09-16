-- =====================================================================
--  Flight Operation · migration_18_aircraft_status_history.sql
--  เก็บประวัติสถานภาพเครื่องราย "วัน" (1 เครื่อง : 1 แถวต่อวัน)
--   • เปลี่ยนสถานภาพในหน้าเว็บ → บันทึกลงประวัติของ "วันนี้" อัตโนมัติ (trigger)
--   • สถานภาพของวันที่ D = แถวประวัติล่าสุดที่ log_date <= D (ถ้าไม่เปลี่ยนก็ค้างค่าเดิม)
--  ต้องรัน migration_17 ก่อน · รันซ้ำได้ ปลอดภัย
-- =====================================================================
create table if not exists public.aircraft_status_history (
  aircraft_id  uuid not null references public.aircraft(id) on delete cascade,
  log_date     date not null default current_date,
  status       aircraft_status not null,
  note         text,
  updated_by   uuid references public.profiles(id) on delete set null,
  updated_at   timestamptz not null default now(),
  primary key (aircraft_id, log_date)
);
create index if not exists idx_ac_hist_date on public.aircraft_status_history(log_date);

alter table public.aircraft_status_history enable row level security;
drop policy if exists p_achist_read on public.aircraft_status_history;
create policy p_achist_read on public.aircraft_status_history for select using ( public.is_active() );
drop policy if exists p_achist_write on public.aircraft_status_history;
create policy p_achist_write on public.aircraft_status_history for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- ทุกครั้งที่สถานภาพ/หมายเหตุเปลี่ยน → เขียนสแนปช็อตของวันนี้ (ทับของวันเดียวกัน)
create or replace function public.snapshot_aircraft_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status
     or new.status_note is distinct from old.status_note then
    insert into public.aircraft_status_history (aircraft_id, log_date, status, note, updated_by, updated_at)
    values (new.id, current_date, new.status, new.status_note, auth.uid(), now())
    on conflict (aircraft_id, log_date)
    do update set status = excluded.status, note = excluded.note,
                  updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;
  return new;
end $$;

drop trigger if exists trg_snapshot_aircraft_status on public.aircraft;
create trigger trg_snapshot_aircraft_status
  after insert or update of status, status_note on public.aircraft
  for each row execute function public.snapshot_aircraft_status();

-- backfill: บันทึกสถานภาพปัจจุบันของทุกเครื่องเป็นแถวของวันนี้ (ถ้ายังไม่มี)
insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
select id, current_date, status, status_note from public.aircraft
on conflict (aircraft_id, log_date) do nothing;

-- สถานภาพของทุกเครื่อง ณ วันที่กำหนด (แถวล่าสุดที่ <= วันนั้น)
create or replace function public.aircraft_status_on(p_date date)
returns table (aircraft_id uuid, status aircraft_status, note text, log_date date)
language sql stable security definer set search_path = public as $$
  select distinct on (h.aircraft_id) h.aircraft_id, h.status, h.note, h.log_date
    from public.aircraft_status_history h
   where h.log_date <= p_date
   order by h.aircraft_id, h.log_date desc;
$$;
