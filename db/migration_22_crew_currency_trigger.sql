-- =====================================================================
--  Flight Operation · migration_22_crew_currency_trigger.sql
--  อัปเดต "วันบินล่าสุด 500/600" ของนักบินอัตโนมัติ เมื่อบันทึกรายงานหลังบิน
--   • ยึดวันจากภารกิจ (mission_date) + แบบเครื่องจาก aircraft.type
--   • ดันเฉพาะตำแหน่งนักบิน (AC/IP/P/CP/N) · ดันไปข้างหน้าเท่านั้น (greatest)
--   • ข้ามภารกิจที่ถูกยกเลิก
--   • security definer เพื่อให้ trigger แก้ crew_members ได้แม้ผู้บันทึกรายงานไม่มีสิทธิ์ plan
--  ต้องรัน migration_21 ก่อน · รันซ้ำได้ ปลอดภัย
-- =====================================================================
create or replace function public.bump_crew_currency()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_date date; v_type text;
begin
  select m.mission_date, a.type into v_date, v_type
    from public.missions m
    join public.aircraft a on a.id = m.aircraft_id
   where m.id = NEW.mission_id and m.status is distinct from 'cancelled';
  if v_date is null or v_type is null then return NEW; end if;

  if v_type ilike '%500%' then
    update public.crew_members c
       set last_500_date = greatest(c.last_500_date, v_date)
      from public.mission_crew mc
     where mc.mission_id = NEW.mission_id and mc.crew_member_id = c.id
       and upper(coalesce(mc.position,'')) in ('AC','IP','P','CP','N');
  elsif v_type ilike '%600%' then
    update public.crew_members c
       set last_600_date = greatest(c.last_600_date, v_date)
      from public.mission_crew mc
     where mc.mission_id = NEW.mission_id and mc.crew_member_id = c.id
       and upper(coalesce(mc.position,'')) in ('AC','IP','P','CP','N');
  end if;
  return NEW;
end $$;

drop trigger if exists trg_bump_crew_currency on public.post_flight_reports;
create trigger trg_bump_crew_currency
  after insert or update on public.post_flight_reports
  for each row execute function public.bump_crew_currency();

-- เก็บตกข้อมูลเดิมให้ทันสมัยทันที (เท่ากับ seed ส่วนท้าย · ดันไปข้างหน้าเท่านั้น)
with flown as (
  select mc.crew_member_id as cid,
         case when a.type ilike '%500%' then 5 when a.type ilike '%600%' then 6 end as tp,
         max(m.mission_date) as d
    from public.mission_crew mc
    join public.missions m on m.id = mc.mission_id
    join public.aircraft a on a.id = m.aircraft_id
    join public.post_flight_reports r on r.mission_id = m.id
   where mc.crew_member_id is not null
     and upper(coalesce(mc.position,'')) in ('AC','IP','P','CP','N')
     and m.status is distinct from 'cancelled'
   group by mc.crew_member_id, 2
)
update public.crew_members c set
  last_500_date = greatest(c.last_500_date, (select d from flown where cid=c.id and tp=5)),
  last_600_date = greatest(c.last_600_date, (select d from flown where cid=c.id and tp=6));
