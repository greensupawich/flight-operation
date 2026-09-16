-- =====================================================================
--  Flight Operation · import_reports_2026_09_16.sql
--  รายงานหลังบิน 16 ก.ย. 2569 — 3 เครื่อง (ตรงกับจุดจอดในกระดาน 16 ก.ย.)
--   • ATR303 (CBY401) MCP 5.8 ชม. · จอด N16 · ข้อขัดข้อง 4
--   • ATR313 (CBY201) MCP 1.0 ชม. · จอด N15 · ไม่มีข้อขัดข้อง
--   • ATR316 (CBY04)  MCP 2.8 ชม. · จอด N14 · ข้อขัดข้อง 1
--  ต้องรัน migration_16 และ import_missions_2026_09_16.sql ก่อน · รันซ้ำได้
--  (บันทึก ชม.บิน → trigger กระจายไป crew_hours + aircraft.total_hours อัตโนมัติ)
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
         || ' · ข้อขัดข้อง ' || coalesce(array_length(p_disc, 1), 0) || ' รายการ';
end $$;

select pg_temp.add_report('2026-09-16', '60303', 5.8, 'MCP', 'N16', array[
  'Fuel Indicator RH อ่านค่าไม่ได้',
  'Fuel Unbalance Show In Flight',
  'Loop B ENG1 self test ไม่ได้ (CAT C เริ่มนับตั้งแต่วันที่ 16 ก.ย.69)',
  'Fuel temp 2 ข้างมีค่าต่างกันประมาณ 10 องศา'
]) as "ผล ATR303"
union all
select pg_temp.add_report('2026-09-16', '60313', 1.0, 'MCP', 'N15', array[]::text[]) as "ผล"
union all
select pg_temp.add_report('2026-09-16', '60316', 2.8, 'MCP', 'N14', array[
  'APM fault ที่พื้น reset ไม่หาย'
]) as "ผล";
