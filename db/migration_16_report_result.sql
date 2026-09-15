-- =====================================================================
--  Flight Operation · migration_16_report_result.sql
--  รายงานหลังบิน: ผลภารกิจ (MCP = Mission Complete) + จุดจอดขากลับ
--   • result          : 'MCP' สำเร็จ · 'INCOMPLETE' ไม่สำเร็จ · 'CANCELLED' ยกเลิก
--   • parking_return  : จุดจอดขากลับจริง (แผนอยู่ที่ missions.parking_in)
--   • สถานะภารกิจ (missions.status) ปรับตามผลภารกิจอัตโนมัติ
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================
alter table public.post_flight_reports
  add column if not exists result text,
  add column if not exists parking_return text;

alter table public.post_flight_reports drop constraint if exists post_flight_reports_result_check;
alter table public.post_flight_reports add constraint post_flight_reports_result_check
  check (result is null or result in ('MCP', 'INCOMPLETE', 'CANCELLED'));

create or replace function public.sync_mission_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    update public.missions set status = 'planned' where id = old.mission_id;
    return old;
  end if;
  update public.missions
     set status = case new.result
                    when 'MCP'        then 'completed'::mission_status
                    when 'CANCELLED'  then 'cancelled'::mission_status
                    else status end
   where id = new.mission_id;
  return new;
end $$;

drop trigger if exists trg_sync_mission_status on public.post_flight_reports;
create trigger trg_sync_mission_status
  after insert or update of result or delete on public.post_flight_reports
  for each row execute function public.sync_mission_status();
