-- =====================================================================
--  Flight Operation · migration_03_crew_roster.sql
--  ทะเบียนลูกเรือ: ใช้ "รหัส (code)" ที่กำหนดเองเป็นตัวระบุตัวตนถาวร
--  เปลี่ยนชื่อ/ยศได้ โดย ชม.บินสะสมยังผูกกับคนเดิม (เพราะยึดรหัส ไม่ยึดชื่อ)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

-- ---------- 1) ตารางทะเบียนลูกเรือ ----------
create table if not exists public.crew_members (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,          -- รหัสที่กำหนดเอง = ตัวตนถาวร
  full_name   text not null,                 -- ชื่อ+ยศ ปัจจุบัน (แก้ได้)
  position    text,                          -- ตำแหน่งหลัก เช่น IP / FM
  note        text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_crew_members_name on public.crew_members(full_name);

-- ---------- 2) ผูกลูกเรือในภารกิจกับทะเบียน ----------
alter table public.mission_crew
  add column if not exists crew_member_id uuid
    references public.crew_members(id) on delete set null;
create index if not exists idx_mission_crew_member on public.mission_crew(crew_member_id);

-- ---------- 3) crew_hours: เปลี่ยนจากผูกบัญชีผู้ใช้ → ผูกทะเบียนลูกเรือ ----------
alter table public.crew_hours
  add column if not exists crew_member_id uuid
    references public.crew_members(id) on delete cascade;
alter table public.crew_hours alter column profile_id drop not null;
alter table public.crew_hours drop constraint if exists crew_hours_profile_id_aircraft_type_key;
create unique index if not exists crew_hours_member_type_key
  on public.crew_hours (crew_member_id, aircraft_type);

-- ---------- 4) สิทธิ์ (RLS) ----------
alter table public.crew_members enable row level security;

drop policy if exists p_crewmem_read on public.crew_members;
create policy p_crewmem_read on public.crew_members for select
  using ( public.is_active() );

drop policy if exists p_crewmem_write on public.crew_members;
create policy p_crewmem_write on public.crew_members for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- อัปเดต updated_at อัตโนมัติ
create or replace function public.touch_crew_member()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists trg_touch_crew_member on public.crew_members;
create trigger trg_touch_crew_member before update on public.crew_members
  for each row execute function public.touch_crew_member();

-- =====================================================================
--  5) trigger กระจาย ชม.บิน — ยึด crew_member_id (ข้าม AC / N เหมือนเดิม)
-- =====================================================================
create or replace function public.distribute_post_flight()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_aircraft_id uuid;
  v_type        text;
  v_delta       numeric(10,2);
begin
  v_delta := new.total_hours - coalesce(old.total_hours, 0);

  select m.aircraft_id, a.type into v_aircraft_id, v_type
  from public.missions m
  left join public.aircraft a on a.id = m.aircraft_id
  where m.id = new.mission_id;

  v_type := coalesce(v_type, '-');

  if v_aircraft_id is not null then
    update public.aircraft set total_hours = total_hours + v_delta where id = v_aircraft_id;
  end if;

  -- group by กันกรณีคนเดียวอยู่หลายตำแหน่งในภารกิจเดียว (นับครั้งเดียว)
  insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
  select mc.crew_member_id, v_type, v_delta, now()
    from public.mission_crew mc
   where mc.mission_id = new.mission_id
     and mc.crew_member_id is not null
     and coalesce(upper(btrim(mc.position)), '') not in ('AC', 'N')
   group by mc.crew_member_id
  on conflict (crew_member_id, aircraft_type)
  do update set total_hours = public.crew_hours.total_hours + excluded.total_hours,
                updated_at  = now();

  return new;
end $$;

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
   from (select distinct mc.crew_member_id
           from public.mission_crew mc
          where mc.mission_id = old.mission_id
            and mc.crew_member_id is not null
            and coalesce(upper(btrim(mc.position)), '') not in ('AC', 'N')) x
  where ch.crew_member_id = x.crew_member_id
    and ch.aircraft_type = v_type;

  return old;
end $$;

-- =====================================================================
--  6) ย้ายข้อมูลเดิม: สร้างทะเบียนจากชื่อที่เคยกรอก แล้วผูก + คิด ชม.ใหม่
--     (ชื่อทดสอบจะกลายเป็นรายชื่อในทะเบียน — แก้ชื่อ/รหัส หรือลบได้ในหน้าเว็บ)
-- =====================================================================
insert into public.crew_members (code, full_name)
select distinct btrim(mc.crew_name), btrim(mc.crew_name)
  from public.mission_crew mc
 where coalesce(btrim(mc.crew_name), '') <> ''
   and not exists (select 1 from public.crew_members c
                    where lower(c.code) = lower(btrim(mc.crew_name)))
on conflict (code) do nothing;

update public.mission_crew mc
   set crew_member_id = c.id
  from public.crew_members c
 where mc.crew_member_id is null
   and lower(btrim(mc.crew_name)) = lower(c.code);

-- คิด ชม.บินสะสมใหม่ทั้งหมดจากรายงานที่มีอยู่
delete from public.crew_hours;

with legit as (
  select distinct m.id as mission_id, mc.crew_member_id,
         coalesce(a.type, '-') as ac_type, r.total_hours
    from public.post_flight_reports r
    join public.missions m       on m.id = r.mission_id
    left join public.aircraft a  on a.id = m.aircraft_id
    join public.mission_crew mc  on mc.mission_id = m.id
   where mc.crew_member_id is not null
     and coalesce(upper(btrim(mc.position)), '') not in ('AC', 'N')
)
insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
select crew_member_id, ac_type, sum(total_hours), now()
  from legit group by crew_member_id, ac_type;

-- =====================================================================
--  ตรวจผล:
--    select c.code, c.full_name, ch.aircraft_type, ch.total_hours
--      from crew_hours ch join crew_members c on c.id = ch.crew_member_id
--     order by ch.total_hours desc;
-- =====================================================================
