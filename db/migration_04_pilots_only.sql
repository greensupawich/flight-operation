-- =====================================================================
--  Flight Operation · migration_04_pilots_only.sql
--  ทะเบียน + ชม.บิน เก็บ "เฉพาะนักบิน" เท่านั้น
--    • ตำแหน่งนักบิน = AC, IP, P, CP, N
--    • นับ ชม.บินจริงเฉพาะ IP, P, CP   (AC และ N ไม่นับ ตามระเบียบ)
--    • FM, RO, LM, AH = กรอกชื่อลงกระดานได้ แต่ไม่เข้าทะเบียน ไม่สะสม ชม.
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

-- ---------- 1) ตัดการผูกทะเบียนออกจากตำแหน่งที่ไม่ใช่นักบิน ----------
update public.mission_crew
   set crew_member_id = null
 where crew_member_id is not null
   and coalesce(upper(btrim(position)), '') not in ('AC', 'IP', 'P', 'CP', 'N');

-- ---------- 2) trigger: นับ ชม.เฉพาะ IP / P / CP ----------
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

  -- เฉพาะนักบินที่นับชั่วโมง: IP, P, CP
  insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
  select mc.crew_member_id, v_type, v_delta, now()
    from public.mission_crew mc
   where mc.mission_id = new.mission_id
     and mc.crew_member_id is not null
     and coalesce(upper(btrim(mc.position)), '') in ('IP', 'P', 'CP')
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
            and coalesce(upper(btrim(mc.position)), '') in ('IP', 'P', 'CP')) x
  where ch.crew_member_id = x.crew_member_id
    and ch.aircraft_type = v_type;

  return old;
end $$;

-- ---------- 3) คิด ชม.บินสะสมใหม่ทั้งหมดตามกติกาใหม่ ----------
delete from public.crew_hours;

with legit as (
  select distinct m.id as mission_id, mc.crew_member_id,
         coalesce(a.type, '-') as ac_type, r.total_hours
    from public.post_flight_reports r
    join public.missions m       on m.id = r.mission_id
    left join public.aircraft a  on a.id = m.aircraft_id
    join public.mission_crew mc  on mc.mission_id = m.id
   where mc.crew_member_id is not null
     and coalesce(upper(btrim(mc.position)), '') in ('IP', 'P', 'CP')
)
insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
select crew_member_id, ac_type, sum(total_hours), now()
  from legit group by crew_member_id, ac_type;

-- =====================================================================
--  หมายเหตุ: รายชื่อในทะเบียนที่เคยถูกสร้างจากตำแหน่งที่ไม่ใช่นักบิน
--  (เช่น ชื่อที่เคยกรอกในช่อง FM/RO/LM/AH) จะยังค้างอยู่ในทะเบียน
--  ให้ลบเองที่หน้า "ทะเบียนนักบิน" — ดูรายชื่อที่ควรพิจารณาลบได้จาก:
--
--    select c.code, c.full_name
--      from crew_members c
--     where not exists (
--             select 1 from mission_crew mc
--              where mc.crew_member_id = c.id
--                and coalesce(upper(btrim(mc.position)),'') in ('AC','IP','P','CP','N'))
--       and not exists (select 1 from crew_hours h where h.crew_member_id = c.id);
-- =====================================================================
