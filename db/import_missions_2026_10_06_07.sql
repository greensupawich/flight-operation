-- =====================================================================
--  Flight Operation · import_missions_2026_10_06_07.sql
--  ภารกิจ 6–7 ต.ค. 2569 (ถอดจากภาพกระดานจัดบิน)
--  • ต้องรัน migration_27 ก่อน
--  • 7 ต.ค. CBY77 "บ.สำรอง รับ 911" — ตำแหน่งบนกระดานแปลงเป็น: ผอ.เดินทาง=AC · นบ.ราชฯ 1=IP · นบ.ราชฯ 2=CP · ตท.=N
--    (T/O = STBY แต่เป็นภารกิจวังจริง ไม่ใช่ชุด STBY)
--  • กล่อง STBY ซ้ายล่าง → ชนิด STBY · ชื่อใต้กล่อง STBY = น.จัดบินของวันนั้น
--  • รันซ้ำได้: ภารกิจที่มี วันที่ + COWBOY + T/O ตรงกันอยู่แล้วจะถูกข้าม
--  รันใน Supabase → SQL Editor
-- =====================================================================

create or replace function pg_temp.match_pilot(p_name text)
returns uuid language plpgsql as $$
declare v_clean text; v_bare text; v_id uuid; n int;
begin
  v_clean := regexp_replace(regexp_replace(coalesce(p_name,''), '\([^)]*\)', '', 'g'), '\s', '', 'g');
  if v_clean = '' then return null; end if;
  select id into v_id from public.crew_members
   where regexp_replace(full_name, '\s', '', 'g') = v_clean limit 1;
  if v_id is not null then return v_id; end if;
  if to_regclass('public.crew_aliases') is not null then
    execute 'select crew_member_id from public.crew_aliases where alias = $1' into v_id using v_clean;
    if v_id is not null then return v_id; end if;
  end if;
  v_bare := regexp_replace(v_clean, '^([^.]{1,3}\.)+', '');
  select count(*), min(id::text)::uuid into n, v_id from public.crew_members
   where regexp_replace(regexp_replace(full_name, '\s', '', 'g'), '^([^.]{1,3}\.)+', '') = v_bare;
  return case when n = 1 then v_id end;
end $$;

create or replace function pg_temp.add_mission(m jsonb)
returns text language plpgsql as $$
declare
  v_date date := (m->>'date')::date;
  v_id uuid; v_ac uuid; v_kind text; v_src text; v_ids uuid[]; missing text;
begin
  if exists (select 1 from public.missions
              where mission_date = v_date and callsign = m->>'callsign'
                and coalesce(takeoff_time, '') = coalesce(m->>'to', '')) then
    return 'ข้าม (มีอยู่แล้ว)';
  end if;

  select id into v_ac from public.aircraft where tail_number = m->>'tail';

  select array_agg(pg_temp.match_pilot(c->>'name')) filter (where pg_temp.match_pilot(c->>'name') is not null),
         string_agg(c->>'name', ', ')            filter (where pg_temp.match_pilot(c->>'name') is null)
    into v_ids, missing
    from jsonb_array_elements(m->'crew') c
   where upper(c->>'pos') in ('AC','IP','P','CP','N');

  if coalesce(m->>'kind_fixed', '') <> '' then
    v_kind := m->>'kind_fixed'; v_src := 'จากไฟล์';
  else
    select qe.kind into v_kind from public.queue_entries qe
     where qe.entry_date = v_date and qe.crew_member_id = any(coalesce(v_ids, '{}'))
       and upper(coalesce(qe.code, '')) <> 'ST'
     group by qe.kind order by count(*) desc, qe.kind limit 1;
    v_src := case when v_kind is not null then 'จากสีในคิวบิน' else 'ค่าเริ่มต้น' end;
    v_kind := coalesce(v_kind, m->>'fallback');
  end if;

  insert into public.missions (mission_date, mission_name, aircraft_id, route, callsign, kind,
         showtime, brief_time, step_time, taxi_time, takeoff_time, fuel, catering, pax,
         head_delegation, poc_name, poc_phone, parking_out, parking_in, remark)
  values (v_date, m->>'name', v_ac, m->>'route', m->>'callsign', v_kind,
         m->>'show', m->>'brief', m->>'step', m->>'taxi', m->>'to', m->>'fuel', m->>'catering', m->>'pax',
         nullif(m->>'head',''), nullif(m->>'poc',''), nullif(m->>'pocTel',''),
         nullif(m->>'out',''), nullif(m->>'in',''), nullif(m->>'remark',''))
  returning id into v_id;

  insert into public.mission_crew (mission_id, position, crew_name, crew_member_id, sort_order)
  select v_id, c->>'pos', c->>'name',
         case when upper(c->>'pos') in ('AC','IP','P','CP','N') then pg_temp.match_pilot(c->>'name') end,
         (o - 1)::int
    from jsonb_array_elements(m->'crew') with ordinality as t(c, o);

  return 'เพิ่ม · ' || v_kind || ' (' || v_src || ')' ||
         coalesce(' · นักบินไม่อยู่ในทะเบียน: ' || missing, '');
end $$;

select x->>'date' as "วันที่", x->>'callsign' as "COWBOY", x->>'to' as "T/O", left(x->>'name', 45) as "ภารกิจ",
       pg_temp.add_mission(x) as "ผล"
  from jsonb_array_elements($json$[
 {
  "kind_fixed": "palace",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0800",
  "step": "0830",
  "taxi": "-",
  "to": "0900",
  "fuel": "4 T",
  "catering": "-",
  "pax": "30",
  "name": "ผลัดเปลี่ยนข้าราชบริพาร 909",
  "route": "บน.6 - บน.41(1300) - บน.6",
  "head": "",
  "poc": "พ.ท.กฤษณ์ เห็นประเสริฐ",
  "pocTel": "08 1700 7313",
  "out": "N16",
  "in": "N16",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.พฤกษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิติพจน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชาติชาย"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ชเนรินทร์"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ภูธเนศ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   }
  ],
  "date": "2026-10-06",
  "tail": "60303",
  "callsign": "CBY04"
 },
 {
  "kind_fixed": "stby",
  "fallback": "stby",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
  "name": "STBY ATR72-500/600",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "",
  "in": "",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ศรราม"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ยุทธพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อรชุน"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎา"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.วินัย"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   }
  ],
  "date": "2026-10-06",
  "tail": null,
  "callsign": "CBY201"
 },
 {
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0600",
  "step": "0610",
  "taxi": "0620",
  "to": "0730",
  "fuel": "4 T",
  "catering": "1 ขา",
  "pax": "30",
  "name": "ส่ง ผบ.ทอ.และคณะฯ",
  "route": "บน.6 - บน.7 - บน.6",
  "head": "พล.อ.อ.เสกสรร คันธา",
  "poc": "น.ท.สุรเมธ อินทนิล",
  "pocTel": "08 6353 0007",
  "out": "RTAF2",
  "in": "N15",
  "remark": "ATR72-500/316 เป็น บ.สำรอง",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.ฉัตฤกษ์"
   },
   {
    "pos": "IP",
    "name": "น.ท.ปรัฒสดางค์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ไกรรัฐ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิรวัฒน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ต.ก้องกิดากร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ประภัสสร"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง มนิชยา"
   }
  ],
  "date": "2026-10-07",
  "tail": "60302",
  "callsign": "CBY01"
 },
 {
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "4 T",
  "catering": "1 ขา",
  "pax": "20",
  "name": "ส่ง ผทค.พิเศษ ทอ.และ คณก.บริหารโครงการพัฒนาและปรับปรุงระบบป้องกันทางอากาศ",
  "route": "บน.6 - ภูเก็ต - บน.6",
  "head": "พล.อ.อ.วิเชียร วิเชียรธรรม",
  "poc": "ร.ท.หญิง จนิลญา ตาวี",
  "pocTel": "08 0496 6109",
  "out": "N14",
  "in": "N14",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.ฐาธิปัตย์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.บัณฑิต"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.ธนภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.อัครวิทย์"
   },
   {
    "pos": "LM",
    "name": "ร.ท.สมพร"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนทวัฒน์"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง รุ่งทิวา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณัฐชา"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง ชัชฎาพร"
   }
  ],
  "date": "2026-10-07",
  "tail": "60313",
  "callsign": "CBY302"
 },
 {
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "",
  "brief": "0800",
  "step": "0830",
  "taxi": "-",
  "to": "0900",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "50/27/-",
  "name": "ส่ง กำลังพล บน.23, บน.21 ช่วยเหลือผู้ประสบอุทกภัยในพื้นที่ภาคกลาง",
  "route": "บน.6 - บน.23 - บน.21 - บน.6",
  "head": "",
  "poc": "น.อ.ธันว์ พฤกษกิจ",
  "pocTel": "06 5692 9789",
  "out": "N16",
  "in": "N16",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "CP",
    "name": "ร.อ.เจษฎา"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ตรัย"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ชลันธร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.พงษ์พิพัฒน์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ศรายุทธ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.นัฐพณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   }
  ],
  "date": "2026-10-07",
  "tail": "60303",
  "callsign": "CBY101"
 },
 {
  "kind_fixed": "palace",
  "fallback": "rtaf",
  "show": "-",
  "brief": "1330",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3.5 T",
  "catering": "ใช้จาก บ.จริง",
  "pax": "31",
  "name": "บ.สำรอง รับ 911 พร้อมผู้ตามเสด็จ และ จนท.สวบ.ทอ.",
  "route": "บน.6 - บน.41(1600) - บก.ทอ.",
  "head": "",
  "poc": "ร.ท.จักพงศ์ ศิริโพธิ์",
  "pocTel": "08 1646 3886",
  "out": "N16",
  "in": "N16",
  "remark": "บ.จริง A320 บริพ 1315 วิ่งขึ้น 1345 · การแต่งกายชุดแขนยาวบ่าอ่อน · ตำแหน่งบนกระดาน: ผอ.เดินทาง=AC, นบ.ราชฯ 1=IP, นบ.ราชฯ 2=CP, ตท.=N · น.เอกสาร ร.ท.ฤทธิเดช นิลทองคำ 09 5551 6915",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.พิชญาณ อะสีติรัตน์"
   },
   {
    "pos": "IP",
    "name": "น.ต.ศรราม"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภานุวัฒน์"
   },
   {
    "pos": "N",
    "name": "ร.ท.ฤทธิเดช"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ถานุพงษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "RO",
    "name": "ร.ต.กันตภณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณัฐริยา"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิกา"
   }
  ],
  "date": "2026-10-07",
  "tail": "60303",
  "callsign": "CBY77"
 },
 {
  "kind_fixed": "stby",
  "fallback": "stby",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
  "name": "STBY ATR72-500/600",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "",
  "in": "",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.วรพงษ์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.สตภัทร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อรชุน"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎา"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   }
  ],
  "date": "2026-10-07",
  "tail": null,
  "callsign": "CBY06"
 }
]$json$::jsonb) with ordinality as t(x, n)
 order by n;

-- น.จัดบินภารกิจ 6–8 ต.ค.
insert into public.day_notes (log_date, duty_officer, duty_phone, updated_at) values
  ('2026-10-06', 'ร.อ.วีระพล', '08 2468 0635', now()),
  ('2026-10-07', 'ร.อ.วีระพล', '08 2468 0635', now()),
  ('2026-10-08', 'ร.อ.ยุทธพล', '08 9919 9065', now())
on conflict (log_date) do update
  set duty_officer = excluded.duty_officer, duty_phone = excluded.duty_phone, updated_at = now();

-- ตรวจผล: ภารกิจทั้งหมด 6–7 ต.ค. (ดูว่ามีซ้ำไหม)
select m.mission_date as "วันที่", m.callsign as "COWBOY", m.takeoff_time as "T/O", m.kind as "ชนิด",
       a.tail_number as "เครื่อง", left(m.mission_name, 40) as "ภารกิจ"
  from public.missions m left join public.aircraft a on a.id = m.aircraft_id
 where m.mission_date between '2026-10-06' and '2026-10-07'
 order by m.mission_date, m.callsign, m.takeoff_time;
