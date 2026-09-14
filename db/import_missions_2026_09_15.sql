-- =====================================================================
--  Flight Operation · import_missions_2026_09_15.sql
--  ภารกิจวันอังคารที่ 15 ก.ย. 2569 (ถอดจากกระดานจัดบิน 4 ภารกิจ)
--   • ต้องรัน catchup_2026_09_14.sql มาก่อน (ชนิดภารกิจ STBY)
--   • รันซ้ำได้: ภารกิจที่มี callsign เดียวกันในวันนั้นอยู่แล้วจะถูกข้าม
--   • ชื่อนักบินผูกกับทะเบียนนักบินอัตโนมัติ (ถ้าชื่อตรง)
--  รันใน Supabase → SQL Editor
-- =====================================================================

create or replace function pg_temp.add_mission(m jsonb)
returns text language plpgsql as $$
declare
  v_id uuid; v_ac uuid; v_member uuid; c jsonb; i int := 0; missing text := '';
begin
  if exists (select 1 from public.missions
              where mission_date = (m->>'date')::date and callsign = m->>'callsign') then
    return 'ข้าม (มีอยู่แล้ว): ' || (m->>'callsign');
  end if;

  select id into v_ac from public.aircraft where tail_number = m->>'tail';

  insert into public.missions (mission_date, mission_name, aircraft_id, route, callsign, kind,
         showtime, brief_time, step_time, taxi_time, takeoff_time, fuel, catering, pax,
         head_delegation, poc_name, poc_phone, parking_out, parking_in, remark)
  values ((m->>'date')::date, m->>'name', v_ac, m->>'route', m->>'callsign', m->>'kind',
         m->>'show', m->>'brief', m->>'step', m->>'taxi', m->>'to', m->>'fuel', m->>'catering', m->>'pax',
         nullif(m->>'head',''), nullif(m->>'poc',''), nullif(m->>'pocTel',''), m->>'out', m->>'in', nullif(m->>'remark',''))
  returning id into v_id;

  for c in select * from jsonb_array_elements(m->'crew') loop
    v_member := null;
    if upper(c->>'pos') in ('AC','IP','P','CP','N') then
      select id into v_member from public.crew_members
       where regexp_replace(full_name, '\s', '', 'g') = regexp_replace(c->>'name', '\s', '', 'g') limit 1;
      if v_member is null then missing := missing || ' ' || (c->>'name'); end if;
    end if;
    insert into public.mission_crew (mission_id, position, crew_name, crew_member_id, sort_order)
    values (v_id, c->>'pos', c->>'name', v_member, i);
    i := i + 1;
  end loop;

  return 'เพิ่ม: ' || (m->>'callsign') || (case when missing <> '' then ' · ไม่พบในทะเบียน:' || missing else '' end);
end $$;

select pg_temp.add_mission(x) as "ผล"
from jsonb_array_elements($json$[
  {
    "date":"2026-09-15", "tail":"60316", "callsign":"CBY201", "kind":"rtaf",
    "show":"-", "brief":"0515", "step":"0530", "taxi":"-", "to":"0600",
    "fuel":"4.5 T", "catering":"-", "pax":"-/20/10",
    "name":"รับ-ส่ง รอง จก.จร.ทอ.และคณะตรวจการปฏิบัติราชการ",
    "route":"บน.6 - บน.56(0900) - ภูเก็ต - บน.6",
    "head":"น.อ.ศักดิ์สิทธิ์ เจริญพจน์",
    "poc":"น.อ.มนธร เด่นดวง", "pocTel":"09 3323 9351",
    "out":"N15", "in":"N15",
    "remark":"บน.56 รับ รอง ผบ.ศซฝล.คปอ.และคณะฯ (10 คน) กลับ บน.6",
    "crew":[
      {"pos":"IP","name":"น.ต.ศรราม"}, {"pos":"P","name":"ร.อ.ฐาธิปัตย์"}, {"pos":"CP","name":"ร.อ.ภวิล"},
      {"pos":"FM","name":"พ.อ.อ.กิตติพศ"}, {"pos":"FM","name":"พ.อ.อ.เจษฎากร"},
      {"pos":"RO","name":"จ.อ.ปฏิภาณ"},
      {"pos":"LM","name":"พ.อ.ท.ปราชชัยญา"}, {"pos":"LM","name":"จ.อ.พจน์สุวัฒน์"}
    ]
  },
  {
    "date":"2026-09-15", "tail":"60303", "callsign":"CBY101", "kind":"training",
    "show":"-", "brief":"0615", "step":"0630", "taxi":"-", "to":"0700",
    "fuel":"3 T", "catering":"-", "pax":"-/32",
    "name":"ฝึกบิน",
    "route":"บน.6 - บน.5 - บน.6",
    "head":"", "poc":"", "pocTel":"",
    "out":"N15", "in":"RTAF2", "remark":"",
    "crew":[
      {"pos":"IP","name":"น.ต.ธนัช"}, {"pos":"P","name":"น.ต.ธนกร"}, {"pos":"CP","name":"ร.อ.ไกรรัฐ"},
      {"pos":"FM","name":"พ.อ.อ.รังสิมันตุ์"}, {"pos":"FM","name":"พ.อ.อ.อุดม"},
      {"pos":"RO","name":"จ.อ.ธีรศักดิ์"},
      {"pos":"LM","name":"พ.อ.อ.ทินวัฒน์"}, {"pos":"LM","name":"พ.อ.อ.กิตติภัฏ"}
    ]
  },
  {
    "date":"2026-09-15", "tail":"60313", "callsign":"CBY05", "kind":"rtaf",
    "show":"-", "brief":"1000", "step":"1030", "taxi":"-", "to":"1100",
    "fuel":"3 T", "catering":"2 ขา", "pax":"15",
    "name":"รับ-ส่ง ราชองครักษ์ประจำพระองค์ และคณะ สนภ.ทอ.",
    "route":"บน.6 - บน.1(1600) - บน.6",
    "head":"พล.อ.ท.โชคดี สมจิตต์",
    "poc":"น.อ.เสือ ลือนาม", "pocTel":"09 7965 2895",
    "out":"N14", "in":"N14", "remark":"",
    "crew":[
      {"pos":"P","name":"ร.อ.นฤดล"}, {"pos":"CP","name":"ร.อ.กิตติคม"},
      {"pos":"FM","name":"พ.อ.อ.ธนดล"}, {"pos":"FM","name":"พ.อ.อ.จิรายุทธ์"},
      {"pos":"RO","name":"พ.อ.ท.พงศกร"},
      {"pos":"LM","name":"พ.อ.อ.ชาญศักดิ์"}, {"pos":"LM","name":"จ.อ.รณกฤต"},
      {"pos":"AH","name":"พ.อ.อ.หญิง วนิดา"}, {"pos":"AH","name":"จ.ท.หญิง ณัฐณิชา"}
    ]
  },
  {
    "date":"2026-09-15", "tail":"60303", "callsign":"CBY77", "kind":"stby",
    "show":"-", "brief":"1330", "step":"STBY", "taxi":"-", "to":"STBY",
    "fuel":"3.5 T", "catering":"ใช้จาก บ.จริง", "pax":"1+26",
    "name":"บ.ที่นั่งสำรอง รับ-ส่ง และ บ.เตรียมพร้อมลำเลียงสายแพทย์ทางอากาศ เจ้าจอม พล.ท.หญิง ท่านผู้หญิงอรอนงค์ ปิยนาฏวชิรพัทธ์",
    "route":"บน.6(พร้อม 1400) - ร้อยเอ็ด - บน.6",
    "head":"",
    "poc":"พ.อ.อิทธิพล นามภูงา", "pocTel":"08 6351 9192",
    "out":"N16", "in":"N16",
    "remark":"การแต่งกายชุดแขนยาวบ่าอ่อน · น.เอกสาร: ร.ท.ชยพล ไวยเนตร 08 6994 7990 · นบ.ราชฯ 1 = IP, นบ.ราชฯ 2 = CP, ตห. = N",
    "crew":[
      {"pos":"IP","name":"น.ต.ธนะภัทร์"}, {"pos":"CP","name":"ร.อ.วรพงษ์"}, {"pos":"N","name":"ร.ท.ชยพล"},
      {"pos":"FM","name":"พ.อ.อ.พงษ์พิพัฒน์"}, {"pos":"FM","name":"พ.อ.อ.ปวีณ์กร"},
      {"pos":"RO","name":"พ.อ.อ.นฤชิต"},
      {"pos":"LM","name":"พ.อ.อ.วัลลภ"}, {"pos":"LM","name":"พ.อ.อ.ยศธน"}
    ]
  }
]$json$::jsonb) as x;

-- ---------- ตรวจผล ----------
select m.callsign as "COWBOY", a.type || '/' || a.tail_number as "เครื่อง", m.kind as "ชนิด",
       m.takeoff_time as "T/O", count(mc.id) as "ลูกเรือ",
       count(mc.crew_member_id) as "นักบินที่ผูกทะเบียน"
  from public.missions m
  left join public.aircraft a on a.id = m.aircraft_id
  left join public.mission_crew mc on mc.mission_id = m.id
 where m.mission_date = '2026-09-15'
 group by m.id, m.callsign, a.type, a.tail_number, m.kind, m.takeoff_time
 order by m.brief_time;
