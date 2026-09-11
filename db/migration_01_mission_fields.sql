-- =====================================================================
--  Flight Operation · migration_01_mission_fields.sql
--  เพิ่มฟิลด์ภารกิจตามฟอร์มจัดบินจริง (A/C, callsign, เวลา, ชพ., PAX, ลูกเรือ ฯลฯ)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

-- ---------- ชนิดภารกิจ: ทอ. / กห. / วัง / ฝึกบิน / อื่นๆ ----------
do $$ begin
  create type mission_kind as enum ('rtaf','mod','palace','training','other');
exception when duplicate_object then null; end $$;

-- ---------- ฟิลด์เพิ่มเติมของภารกิจ ----------
alter table public.missions
  add column if not exists callsign          text,          -- CBY01 / COWBOY 601
  add column if not exists kind              mission_kind not null default 'other',
  add column if not exists showtime          text,          -- SHOWTIME
  add column if not exists brief_time        text,          -- BRIEF
  add column if not exists step_time         text,          -- STEP
  add column if not exists taxi_time         text,          -- TAXI
  add column if not exists takeoff_time      text,          -- T/O
  add column if not exists fuel              text,          -- ชพ. เช่น "3.5 T" / "STBY"
  add column if not exists catering          text,          -- จัดรับรอง เช่น "1 ขา"
  add column if not exists pax               text,          -- PAX. เช่น "35" / "-/-/20"
  add column if not exists head_delegation   text,          -- หน.คณะฯ
  add column if not exists poc_name          text,          -- ชื่อ POC
  add column if not exists poc_phone         text,          -- เบอร์ POC
  add column if not exists parking_out       text,          -- จุดจอด "ไป"  เช่น N14
  add column if not exists parking_in        text,          -- จุดจอด "กลับ" เช่น N14 / RTAF
  add column if not exists distance          text,          -- ระยะทาง
  add column if not exists duration          text,          -- เวลา
  add column if not exists altitude          text,          -- ความสูง
  add column if not exists remark            text;          -- หมายเหตุ

-- =====================================================================
--  ลูกเรือ: รองรับ "ชื่อ" ที่ไม่ใช่ผู้ใช้ในระบบ
--   - crew_name  = ชื่อที่แสดงบนฟอร์ม (บังคับ)
--   - profile_id = ผูกกับบัญชีผู้ใช้ (ไม่บังคับ) — ถ้าผูกไว้ ชม.บินจะสะสมให้คนนั้น
-- =====================================================================
alter table public.mission_crew
  add column if not exists crew_name text;

-- profile_id ไม่บังคับอีกต่อไป
alter table public.mission_crew alter column profile_id drop not null;

-- ปลดข้อจำกัดเดิม (mission_id, profile_id) เพราะ profile_id ว่างได้ และ
-- ตำแหน่งหนึ่งมีได้หลายคน (เช่น IP 2 คน, FM 2 คน)
alter table public.mission_crew
  drop constraint if exists mission_crew_mission_id_profile_id_key;

-- ลำดับการแสดงผลในฟอร์ม
alter table public.mission_crew
  add column if not exists sort_order int not null default 0;

-- =====================================================================
--  แก้ trigger กระจาย ชม.บิน
--  ⚠️ AC และ N "ไม่นับ" ชั่วโมงบิน (ตามระเบียบการจัดบิน)
--     และนับเฉพาะลูกเรือที่ผูกกับบัญชีผู้ใช้ (profile_id ไม่ว่าง)
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

  -- ชม.เครื่องสะสม
  if v_aircraft_id is not null then
    update public.aircraft set total_hours = total_hours + v_delta where id = v_aircraft_id;
  end if;

  -- ชม.ลูกเรือ — ข้าม AC และ N
  insert into public.crew_hours (profile_id, aircraft_type, total_hours, updated_at)
  select mc.profile_id, v_type, v_delta, now()
    from public.mission_crew mc
   where mc.mission_id = new.mission_id
     and mc.profile_id is not null
     and coalesce(upper(btrim(mc.position)), '') not in ('AC', 'N')
  on conflict (profile_id, aircraft_type)
  do update set total_hours = public.crew_hours.total_hours + excluded.total_hours,
                updated_at  = now();

  return new;
end $$;

-- ย้อนกลับตอนลบรายงาน — ต้องข้าม AC/N เหมือนกัน
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
    and mc.profile_id is not null
    and coalesce(upper(btrim(mc.position)), '') not in ('AC', 'N')
    and ch.profile_id = mc.profile_id
    and ch.aircraft_type = v_type;

  return old;
end $$;

-- =====================================================================
--  เสร็จ — ตรวจผลได้ที่ Table Editor → missions (ควรเห็นคอลัมน์ใหม่)
-- =====================================================================
