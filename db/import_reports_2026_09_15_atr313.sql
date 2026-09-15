-- =====================================================================
--  Flight Operation · import_reports_2026_09_15_atr313.sql
--  รายงานหลังบิน 15 ก.ย. 2569 (เพิ่มเติม)
--   • ATR313 MCP 1.4 ชม. · จอด N14 · ข้อขัดข้อง 1
--  แยกไฟล์จาก import_reports_2026_09_15.sql เพื่อไม่เขียนทับรายงานของ ATR316/303
--  ที่อาจแก้ไขในหน้าเว็บไปแล้ว · ต้องรัน migration_16 ก่อน · รันซ้ำได้
--  รันใน Supabase → SQL Editor
-- =====================================================================
create or replace function pg_temp.add_report(p_date date, p_tail text, p_hours numeric,
                                               p_result text, p_parking text, p_disc text[])
returns text language plpgsql as $$
declare v_mid uuid; v_ac uuid; v_cs text; n int; d text;
begin
  select count(*) into n
    from public.missions m join public.aircraft a on a.id = m.aircraft_id
   where m.mission_date = p_date and a.tail_number = p_tail
     and m.kind <> 'stby' and upper(coalesce(m.takeoff_time, '')) <> 'STBY';
  if n <> 1 then
    return 'ATR' || right(p_tail, 3) || ': พบภารกิจที่บินจริง ' || n || ' รายการ — ไม่ได้บันทึก (กรอกเองในหน้ารายงาน)';
  end if;

  select m.id, m.aircraft_id, m.callsign into v_mid, v_ac, v_cs
    from public.missions m join public.aircraft a on a.id = m.aircraft_id
   where m.mission_date = p_date and a.tail_number = p_tail
     and m.kind <> 'stby' and upper(coalesce(m.takeoff_time, '')) <> 'STBY';

  insert into public.post_flight_reports (mission_id, total_hours, result, parking_return)
  values (v_mid, p_hours, p_result, p_parking)
  on conflict (mission_id) do update
     set total_hours = excluded.total_hours, result = excluded.result, parking_return = excluded.parking_return;

  foreach d in array p_disc loop
    insert into public.discrepancies (aircraft_id, mission_id, description, reported_date)
    select v_ac, v_mid, d, p_date
     where not exists (select 1 from public.discrepancies where mission_id = v_mid and description = d);
  end loop;

  return 'ATR' || right(p_tail, 3) || ' → ' || v_cs || ': ' || p_result || ' ' || p_hours || ' ชม. · จอด ' || p_parking
         || ' · ข้อขัดข้อง ' || array_length(p_disc, 1) || ' รายการ';
end $$;

select pg_temp.add_report('2026-09-15', '60313', 1.4, 'MCP', 'N14', array[
  'ADU กระพริบก่อนวิ่งขึ้น Reset C/B แล้วหาย'
]) as "ผล";
