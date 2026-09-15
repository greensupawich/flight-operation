-- =====================================================================
--  Flight Operation · import_missions_2026_09.sql
--  ภารกิจเดือนกันยายน 2569 (1–15 ก.ย.) จากไฟล์ "จัดบิน ฝูง.603 15 ก.ย.69.xlsx"
--  49 ภารกิจ (รวมชุด STBY ประจำวันจากกล่องด้านซ้ายของแต่ละวัน)
--
--  • ต้องรัน catchup_2026_09_14.sql มาก่อน
--  • รันซ้ำได้: ภารกิจที่มี วันที่ + COWBOY + T/O ตรงกันอยู่แล้วจะถูกข้าม
--    (จึงไม่ซ้ำกับ import_missions_2026_09_15.sql ที่อาจรันไปแล้ว)
--  • ชนิดภารกิจ (ไฟล์ไม่มีสีหัวการ์ด):
--      STEP/T-O = STBY หรือกล่อง STBY  → STBY
--      ชื่อมี F.C.F / เดโชชัย           → ตามนั้น
--      นอกนั้น → ใช้สีในคิวบินของนักบินในภารกิจวันนั้น (ข้อมูลที่นำเข้าไว้ 1–14 ก.ย.)
--      ถ้าไม่มี → ฝึกบิน (ถ้าชื่อขึ้นต้นว่า ฝึกบิน) หรือ ภารกิจ ทอ.
--  • ชื่อนักบินผูกทะเบียน: ตัดหมายเหตุในวงเล็บ เช่น (FAM) ออกก่อน · ถ้ายศไม่ตรง
--    (เช่น ร.ท.→ร.อ.) จะเทียบจากชื่ออย่างเดียว เมื่อมีนักบินชื่อนั้นคนเดียว
--  รันใน Supabase → SQL Editor
-- =====================================================================

-- ---------- ซ่อม: ภารกิจที่ STEP หรือ T/O เป็น STBY แต่ชนิดไม่ใช่ STBY ----------
-- (เกิดได้ถ้าเคยรัน catchup/migration_07 รุ่นก่อนแก้ ซ้ำหลังนำเข้าภารกิจ STBY)
update public.missions set kind = 'stby'
 where mission_date between '2026-09-01' and '2026-09-30'
   and kind <> 'stby'
   and (upper(coalesce(step_time, '')) = 'STBY' or upper(coalesce(takeoff_time, '')) = 'STBY');

create or replace function pg_temp.match_pilot(p_name text)
returns uuid language plpgsql as $$
declare v_clean text; v_bare text; v_id uuid; n int;
begin
  v_clean := regexp_replace(regexp_replace(coalesce(p_name,''), '\([^)]*\)', '', 'g'), '\s', '', 'g');
  if v_clean = '' then return null; end if;
  select id into v_id from public.crew_members
   where regexp_replace(full_name, '\s', '', 'g') = v_clean limit 1;
  if v_id is not null then return v_id; end if;
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

select x->>'date' as "วันที่", x->>'callsign' as "COWBOY", x->>'to' as "T/O",
       left(x->>'name', 40) as "ภารกิจ", pg_temp.add_mission(x) as "ผล"
  from jsonb_array_elements($json$[
 {
  "date": "2026-09-01",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.ณัฐชัย"
   },
   {
    "pos": "IP",
    "name": "น.ต.ธนะภัทร์"
   },
   {
    "pos": "P",
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "P",
    "name": "ร.อ.ฐาธิปัตย์ (FAM)"
   },
   {
    "pos": "CP",
    "name": "ร.ท.วสุพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.บุญลือ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิรวัฒน์"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วราภรณ์ ธ."
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ณัฐณิชา"
   }
  ],
  "tail": "60303",
  "callsign": "CBY02",
  "show": "-",
  "brief": "0600",
  "step": "0630",
  "taxi": "-",
  "to": "0700",
  "fuel": "4 T",
  "catering": "2 ขา",
  "pax": "25/-/31",
  "route": "บน.6 - ภูเก็ต - หาดใหญ่(1400) - บน.6",
  "out": "RTAF2",
  "in": "",
  "name": "(1) ส่ง รอง เสธ.ทอ.(กบ.) และ คณะฯ / (2) รับ รมว.กห.และคณะฯ",
  "head": "(1) พล.อ.ท.สันติ แก้วสนธิ / (2) พล.ท.อดุลย์ บุญธรรมเจริญ",
  "poc": "(1) น.ท.ณัฐนัย 08 9154 5919 / (2) พ.อ.หญิง ธัญญรัตน์ 09 1847 4474",
  "pocTel": "",
  "remark": "ปฏิบัติ บ.สำรอง นายกฯ",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-01",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ชยพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธนดล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.พงษ์พิพัฒน์"
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
  "tail": "60302",
  "callsign": "CBY101",
  "show": "-",
  "brief": "0615",
  "step": "0630",
  "taxi": "-",
  "to": "0700",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "-",
  "route": "บน.6 - บน.23 - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "ฝึกบิน",
  "head": "",
  "poc": "",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "",
  "fallback": "training"
 },
 {
  "date": "2026-09-01",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.บดีพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ต.ปราชชัยญา"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง ธิติกุล"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง วิภารัตน์"
   }
  ],
  "tail": "60313",
  "callsign": "CBY401",
  "show": "-",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "3 T",
  "catering": "2 ขา",
  "pax": "25",
  "route": "บน.6 - ร้อยเอ็ด(1500) - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "รับ-ส่ง รองหัวหน้าส่วนราชการฝ่ายบริหารพระตำหนักราชฤทธิ์รุ่งโรจน์ฯ และคณะสำรวจพื้นที่ฯ",
  "head": "พล.ต.ท.มณฑลทัฬห์ บุนนาค",
  "poc": "พ.อ.อิทธิพล นามภูงา",
  "pocTel": "08 6351 9192",
  "remark": "*จัดอาหารเช้าให้คณะ (มีพระสงฆ์ 1 รูป)",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-01",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.วิทวัส"
   },
   {
    "pos": "IP",
    "name": "น.ท.สุทธิรัตน์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ศุภวิชญ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ถานุพงษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.สัมพันธ์"
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
    "name": "พ.อ.อ.หญิง วนิดา"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง มนิชยา"
   }
  ],
  "tail": "60302",
  "callsign": "CBY01",
  "show": "-",
  "brief": "1030",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "4 T",
  "catering": "1 ขา",
  "pax": "-/32",
  "route": "บน.6 - บน.7(รอประสาน) - บน.6",
  "out": "N14",
  "in": "RTAF2",
  "name": "บ.สำรอง รับ ผบ.ทอ.และคณะฯ",
  "head": "พล.อ.อ.เสกสรร คันธา",
  "poc": "น.อ.ดลดิเรก ทองโสภา",
  "pocTel": "09 1915 4599",
  "remark": "บ.จริง A319 วิ่งขึ้น 1045 บรีฟ 1015",
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-01",
  "tail": null,
  "callsign": "CBY04",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ยุทธพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รังสิมันตุ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.พงศ์ณภัทร์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นฤชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-02",
  "tail": null,
  "callsign": "CBY201",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "ร.อ.วีระพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิติพจน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อรชุน"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-03",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ท.สุทธิรัตน์"
   },
   {
    "pos": "P",
    "name": "ร.อ.ฐาธิปัตย์ (ฝนบ.1 9)"
   },
   {
    "pos": "CP",
    "name": "ร.ท.วสุพล"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ชยพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.บุญลือ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.พงศ์ณภัทร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   }
  ],
  "tail": "60302",
  "callsign": "CBY01",
  "show": "-",
  "brief": "0515",
  "step": "0530",
  "taxi": "-",
  "to": "0600",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "-",
  "route": "บน.6 - บน.2 - บน.3 - อู่ตะเภา - บน.6",
  "out": "N15",
  "in": "N15",
  "name": "ตรวจสอบมาตรฐานการบิน",
  "head": "",
  "poc": "",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-03",
  "crew": [
   {
    "pos": "P",
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.ท.พฤกษ์"
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
    "name": "พ.อ.อ.นฤชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.พจน์สุวัฒน์"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วนิดา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง รุ่งทิวา"
   }
  ],
  "tail": "60303",
  "callsign": "CBY04",
  "show": "-",
  "brief": "0615",
  "step": "0630",
  "taxi": "-",
  "to": "0700",
  "fuel": "4 T",
  "catering": "1 ขา",
  "pax": "35",
  "route": "บน.6 - ภูเก็ต(0930) - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "รับ รอง เสธ.ทอ.(กบ.) และ คณก.บริหารโครงการพัฒนาและปรับปรุงระบบป้องกันทางอากาศ",
  "head": "",
  "poc": "น.ท.ภูวนาท ละครวงษ์",
  "pocTel": "06 1550 9250",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-03",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "CP",
    "name": "ร.อ.บัณฑิต"
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
    "pos": "FM",
    "name": "พ.อ.อ.จีระ"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นิรวิทธ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   }
  ],
  "tail": "60313",
  "callsign": "CBY101",
  "show": "-",
  "brief": "0815",
  "step": "0830",
  "taxi": "-",
  "to": "0900",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "-",
  "route": "บน.6 - บน.23 - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "ฝึกบิน",
  "head": "",
  "poc": "",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "",
  "fallback": "training"
 },
 {
  "date": "2026-09-03",
  "tail": null,
  "callsign": "CBY301",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนกร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ไกรรัฐ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รณชัย"
   },
   {
    "pos": "RO",
    "name": "ร.ต.กันตภณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.กิตติภัฏ"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-04",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.ฉัตฤกษ์"
   },
   {
    "pos": "P",
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.ท.พฤกษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อุดม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิกา"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง ชัชฎาพร"
   }
  ],
  "tail": "60302",
  "callsign": "CBY04",
  "show": "-",
  "brief": "0415",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3.5 T",
  "catering": "ใช้จาก บ.จริง",
  "pax": "30",
  "route": "บน.6 - บน.7(0630) - บน.6",
  "out": "N15",
  "in": "RTAF2",
  "name": "บ.สำรอง รับ ผบ.ทอ.และคณะฯ",
  "head": "พล.อ.อ.เสกสรร คันธา",
  "poc": "น.ต.หญิง กานต์ชนก จรรยารักษ์",
  "pocTel": "09 1414 5387",
  "remark": "บ.จริง A320 วิ่งขึ้นจาก บน.6 0415 บรีฟ 0400",
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-04",
  "crew": [
   {
    "pos": "IP",
    "name": "น.อ.ชญานิน"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "ร.ท.สมพร"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนท์วัฒน์"
   }
  ],
  "tail": "60303",
  "callsign": "CBY111",
  "show": "-",
  "brief": "0900",
  "step": "0930",
  "taxi": "-",
  "to": "0945",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "15",
  "route": "บน.6 - บน.21(1100) - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "รับ จนท.ฝูง.211 สนับสนุนการบินหน่วยบินเดโชชัย",
  "head": "",
  "poc": "ร.อ.ปารมี เลิศศรีสันทัด",
  "pocTel": "08 6367 5562",
  "remark": "",
  "kind_fixed": "dechochai",
  "fallback": "dechochai"
 },
 {
  "date": "2026-09-04",
  "tail": null,
  "callsign": "CBY311",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนบัตร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ไกรรัฐ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ปวีณ์กร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิราวัฒน์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ศรายุทธ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.นัฐพณ"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-05",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ศรราม"
   },
   {
    "pos": "CP",
    "name": "ร.อ.สตภัทร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธนดล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ศรายุทธ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนทวัฒน์"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง มนิชยา"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง ชัชฏาพร"
   }
  ],
  "tail": "60302",
  "callsign": "CBY201",
  "show": "-",
  "brief": "0645",
  "step": "0700",
  "taxi": "-",
  "to": "0730",
  "fuel": "3.5 T",
  "catering": "1 ขา",
  "pax": "-/34",
  "route": "บน.6 - บน.7(1030) - บน.6",
  "out": "N15",
  "in": "N15",
  "name": "รับ ราชองครักษ์ประจำพระองค์ และข้าราชบริพาร ส่วนล่วงหลัง HMSV พร้อมพระราชสัมภาระ",
  "head": "น.อ.กฤษณะ สุขดี",
  "poc": "น.อ.กฤษณะ สุขดี",
  "pocTel": "09 8991 5362",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-05",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ท.สุทธิรัตน์"
   },
   {
    "pos": "IP",
    "name": "น.ต.ธนบัตร"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ตรัย"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.ธนชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.วัลลภ"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   }
  ],
  "tail": "60303",
  "callsign": "CBY311",
  "show": "-",
  "brief": "0845",
  "step": "0900",
  "taxi": "-",
  "to": "0930",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "35/20/-",
  "route": "บน.6 - บน.7(1100) - บน.2 - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "รับ-ส่ง จนท.ฝูง.201 พร้อมสัมภาระ",
  "head": "",
  "poc": "น.ต.พัฒนพงษ์ พรหมพันธ์",
  "pocTel": "08 2799 2736",
  "remark": "จาก บน.6 รับ จนท.ขส.ทอ.จำนวน 35 คน ไปส่งที่ บน.7",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-05",
  "tail": null,
  "callsign": "CBY401",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ปวีณ์กร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.บุญลือ"
   },
   {
    "pos": "RO",
    "name": "ร.ต.กันตภณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.พจน์สุวัฒน์"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-06",
  "tail": null,
  "callsign": "CBY05",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.วีระพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รณชัย"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ชเนรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.กิตติภัฎ"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-07",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.วันทชัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ยุทธพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ศตวรรษ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ปวีณ์กร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง วิภารัตน์"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง ชัชฏาพร"
   }
  ],
  "tail": "60302",
  "callsign": "CBY03",
  "show": "-",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "3.5 T",
  "catering": "2 ขา",
  "pax": "20/20",
  "route": "บน.6 - นครศรีธรรมราช(รอรับ/1230) - บน.6",
  "out": "N15",
  "in": "N15",
  "name": "รับ-ส่ง ราชองครักษ์ประจำพระองค์ และคณะสำรวจพื้นที่เตรียมการเสด็จ 906",
  "head": "พล.ท.กฤดิกร คงอุทัยกุล",
  "poc": "พ.ต.กฤษณพล สารบรรณ",
  "pocTel": "09 6192 0003",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-07",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ท.วรุตม์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ฤทธิเดช"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธนดล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ศรายุทธ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ยศธน"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิกา"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ณัฐณิชา"
   }
  ],
  "tail": "60303",
  "callsign": "CBY212",
  "show": "-",
  "brief": "0730",
  "step": "0800",
  "taxi": "-",
  "to": "0830",
  "fuel": "3 T",
  "catering": "2 ขา",
  "pax": "15/15",
  "route": "บน.6 - บน.1(รอรับ/1230) - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "รับ-ส่ง ราชองครักษ์ประจำพระองค์ และคณะสำรวจพื้นที่เตรียมรับ ผู้แทนพระองค์",
  "head": "น.อ.คมสัน สอนสุภาพ ร.น.",
  "poc": "น.ส.สาริศา สว่างวราลี",
  "pocTel": "06 1894 4559",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-07",
  "tail": null,
  "callsign": "CBY02",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนะภัทร์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ณัฐกิจ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.ธนชิต"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนทวัฒน์"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-08",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.บวรรัตน์"
   },
   {
    "pos": "P",
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
   },
   {
    "pos": "LM",
    "name": "ร.ท.สมพร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิกา"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ณัฐณิชา"
   }
  ],
  "tail": "60303",
  "callsign": "CBY04",
  "show": "-",
  "brief": "0440",
  "step": "0450",
  "taxi": "0500",
  "to": "0615",
  "fuel": "3.8 T",
  "catering": "2 ขา",
  "pax": "38/36",
  "route": "บน.6 - บน.41(1900) - บน.6",
  "out": "RTAF2",
  "in": "RTAF2",
  "name": "รับ-ส่ง ปล.กห.และคณะฯ ส่ง คณะจนท.บริหารโครงการจัดหาเครื่องบินโจมตีเบา",
  "head": "พล.อ.ธราพงษ์ มะละคำ",
  "poc": "(1) พ.อ.ชนะศึก อัมพรมุนี 08 9585 0222 / (2) น.ท.ศรัณ วัฒนานุกิจ 08 1806 6444",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-08",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ศรราม"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ณัฐกิจ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ถานุพงษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.พงศ์ณภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ชเนรินทร์"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง ธิติกุล"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง วิภารัตน์"
   }
  ],
  "tail": "60313",
  "callsign": "CBY201",
  "show": "-",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "3.5 T",
  "catering": "1 ขา",
  "pax": "25",
  "route": "บน.6 - ขอนแก่น - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "ส่ง ราชองครักษ์ประจำพระองค์ และคณะสำรวจพื้นที่เตรียมการเสด็จ 905",
  "head": "พล.ท.ฉกาจ ประสงค์",
  "poc": "พ.อ.สมัชชา จิตร์ชูชื่น",
  "pocTel": "08 5960 0192",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-08",
  "tail": null,
  "callsign": "CBY03",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.วันทชัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อมรเทพ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.บุญลือ"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.อัครวิทย์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.พจน์สุวัฒน์"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-08",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.บวรรัตน์"
   },
   {
    "pos": "P",
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
   },
   {
    "pos": "LM",
    "name": "ร.ท.สมพร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิกา"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ณัฐณิชา"
   }
  ],
  "tail": "60302",
  "callsign": "CBY04",
  "show": "-",
  "brief": "STBY",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3.5 T",
  "catering": "ใช้จาก บ.จริง",
  "pax": "38/36",
  "route": "บน.6 - บน.41(1900) - บน.6",
  "out": "N16",
  "in": "RTAF2",
  "name": "บ.สำรอง รับ-ส่ง ปล.กห.และคณะฯ ส่ง คณะจนท.บริหารโครงการจัดหาเครื่องบินโจมตีเบา",
  "head": "พล.อ.ธราพงษ์ มะละคำ",
  "poc": "(1) พ.อ.ชนะศึก อัมพรมุนี 08 9585 0222 / (2) น.ท.ศรัณ วัฒนานุกิจ 08 1806 6444",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-09",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.พงศ์พรเทพ ไสยจิตร"
   },
   {
    "pos": "IP",
    "name": "น.ท.สุทธิรัตน์"
   },
   {
    "pos": "IP",
    "name": "น.ต.วันทชัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.พฤกษ์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ตรัย"
   },
   {
    "pos": "N",
    "name": "ร.อ.บัณฑิต"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎา"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.พงศ์ณภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.วินัย"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง รุ่งทิวา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วนิดา"
   }
  ],
  "tail": "60303",
  "callsign": "CBY316",
  "show": "-",
  "brief": "0500",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3.5 T",
  "catering": "ใช้จาก บ.จริง",
  "pax": "32/43",
  "route": "บน.6 - วัดไต - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "บ.สำรอง ส่ง รมว.กห., ผบ.ทสส.และคณะฯ",
  "head": "พล.ท.อดุลย์ บุญธรรมเจริญ",
  "poc": "น.อ.ยอดทนง พัดประดิษฐ ร.น.",
  "pocTel": "09 5227 8887",
  "remark": "บรีฟห้องประชุมฝูง603 · บ.จริง A320 บรีฟ 0445 วิ่งขึ้น 0700",
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-09",
  "crew": [
   {
    "pos": "P",
    "name": "น.ต.ธนกร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ไกรรัฐ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อมรเทพ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.บุญลือ"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.กิตติภัฏ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง วิภารัตน์"
   }
  ],
  "tail": "60302",
  "callsign": "CBY301",
  "show": "-",
  "brief": "0630",
  "step": "0640",
  "taxi": "0650",
  "to": "0800",
  "fuel": "4 T",
  "catering": "2 ขา",
  "pax": "20/5",
  "route": "บน.6 - นครศรีธรรมราช(1400)-บน.6",
  "out": "RTAF1",
  "in": "RTAF2",
  "name": "(1) ส่ง นายพลากร สุวรรณรัฐ องคมนตรี เป็นผู้แทนพระองค์ และคณะฯ / (2) รับ พล.อ.ดาว์พงษ์ รัตนสุวรรณ องคมนตรี และคณะฯ",
  "head": "(1) นายพลากร สุวรรณรัฐ / (2) พล.อ.ดาว์พงษ์ รัตนสุวรรณ",
  "poc": "(1) ว่าที่ ร.ต.หญิง ธนานิษฐ์ เอกธนาพุฒิโรจน์ 08 1235 4946 / (2) ว่าที่ ร.ต.วิศรุต กวินประกอบสิน 09 2932 9949",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-09",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ศุภวิชญ์"
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
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วราภรณ์ ธ."
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง มนิชยา"
   }
  ],
  "tail": "60303",
  "callsign": "CBY401",
  "show": "-",
  "brief": "0700",
  "step": "0710",
  "taxi": "0720",
  "to": "0830",
  "fuel": "3 T",
  "catering": "1 ขา",
  "pax": "26/-",
  "route": "บน.6 - หัวหิน - บน.6",
  "out": "RTAF2",
  "in": "N14",
  "name": "ส่ง ผช.ผบ.ทอ.(กษ.) และ คณก.บริหารการชดเชยการนำเข้ายุทโธปกรณ์ของ ทอ.",
  "head": "พล.อ.อ.ประภาส สอนใจดี",
  "poc": "น.ท.รวินท์ พินิจจันทร์",
  "pocTel": "08 6365 8115",
  "remark": "รอง จก.สอ.ทอ. ไปแทน ผช.ผบ.ทอ.(กษ.)",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-09",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "CP",
    "name": "ร.อ.บดีพล"
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
    "name": "พ.อ.ต.ธนภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นฤชิต"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ยศธน"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณิชชารีย์"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ชุติกาญจน์"
   }
  ],
  "tail": "60313",
  "callsign": "CBY101",
  "show": "-",
  "brief": "0800",
  "step": "0830",
  "taxi": "-",
  "to": "0900",
  "fuel": "4.3 T",
  "catering": "2 ขา",
  "pax": "18/22",
  "route": "บน.6 - บน.41(1130) - ขอนแก่น(1430) - บน.6",
  "out": "N15",
  "in": "N15",
  "name": "(1) ส่ง คณะกรรมการตรวจรับเรดาร์ / (2) รับ ราชองครักษ์ประจำพระองค์ และคณะสำรวจพื้นเตรียมการเสด็จ 905",
  "head": "(1) พล.อ.อ.ชาตินนท์ สท้านผไท / (2) พล.ท.ฉกาจ ประสงค์",
  "poc": "(1) น.อ.ชัยรัตน์ ทองประไพ 06 2818 8032 / (2) พ.อ.สมัชชา จิตร์ชูชื่น 08 5960 0192",
  "pocTel": "",
  "remark": "จัดรับรองขา บน.6 - บน.41, ขอนแก่น - บน.6 · จาก บน.41 รับผู้โดยสาร 6 คน กลับ บน.6",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-09",
  "tail": null,
  "callsign": "CBY05",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ยุทธพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รณชัย"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นิรวิทธ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-10",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ณภัทร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.มหินทรา"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รณชัย"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.ธนภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิกา"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง มนิชยา"
   }
  ],
  "tail": "60302",
  "callsign": "CBY05",
  "show": "-",
  "brief": "0430",
  "step": "0440",
  "taxi": "0450",
  "to": "0600",
  "fuel": "3.5 T",
  "catering": "3 ขา",
  "pax": "40",
  "route": "บน.6 - บน.41(1100) - แม่สอด(1600) - บน.6",
  "out": "RTAF2",
  "in": "RTAF2",
  "name": "รับ-ส่ง องคมนตรีและคณะฯ",
  "head": "พล.อ.ไพบูลย์ คุ้มฉายา",
  "poc": "นายวิโรจน์ สายวิภู",
  "pocTel": "09 3636 6155",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-10",
  "crew": [
   {
    "pos": "P",
    "name": "น.ต.ธนกร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.บัณฑิต"
   },
   {
    "pos": "N",
    "name": "ร.ท.จาตุรนต์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ศตวรรษ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อุดม"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นิรวิทธ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.พจน์สุวัฒน์"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณิชชารีย์"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง ธิติกุล"
   }
  ],
  "tail": "60316",
  "callsign": "CBY301",
  "show": "-",
  "brief": "0645",
  "step": "0700",
  "taxi": "-",
  "to": "0730",
  "fuel": "3.5 T",
  "catering": "2 ขา",
  "pax": "-",
  "route": "บน.6 - เชียงราย - บน.6",
  "out": "N15",
  "in": "N15",
  "name": "ฝึกบิน",
  "head": "",
  "poc": "",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "",
  "fallback": "training"
 },
 {
  "date": "2026-09-10",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนะภัทร์"
   },
   {
    "pos": "P",
    "name": "ร.อ.วรพงษ์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ยุทธพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธนดล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ต.ก้องกิดากร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ชุติกาญจน์"
   }
  ],
  "tail": "60313",
  "callsign": "CBY02",
  "show": "-",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "3.5 T",
  "catering": "2 ขา",
  "pax": "19",
  "route": "บน.6 - บน.23(1430) - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "รับ-ส่ง ผอ.สนผ.ยก.ทอ.และคณะตรวจรับรองและตรวจติดตามและมาตรฐาน ลูกยางยกระดับสายเคเบิ้ล",
  "head": "พล.อ.ต.เจริญ วัฒนศรีมงคล",
  "poc": "น.อ.พงศ์นที ทุมมานนท์",
  "pocTel": "09 6965 0664",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-10",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.พงศ์พรเทพ ไสยจิตร"
   },
   {
    "pos": "IP",
    "name": "น.ท.สุทธิรัตน์"
   },
   {
    "pos": "IP",
    "name": "น.ต.วันทชัย"
   },
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.พฤกษ์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ตรัย"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎา"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.พงศ์ณภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.วินัย"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง รุ่งทิวา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วนิดา"
   }
  ],
  "tail": "60303",
  "callsign": "CBY316",
  "show": "-",
  "brief": "0900",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3.5 T",
  "catering": "ใช้จาก บ.จริง",
  "pax": "-/43",
  "route": "บน.6 - วัดไต - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "บ.สำรอง รับ รมว.กห., ผบ.ทสส.และคณะฯ",
  "head": "พล.ท.อดุลย์ บุญธรรมเจริญ",
  "poc": "น.อ.ยอดทนง พัดประดิษฐ ร.น.",
  "pocTel": "09 5227 8887",
  "remark": "บ.จริง A320 วิ่งขึ้น 1000",
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-10",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "P",
    "name": "ร.อ.ฐาธิปัตย์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ณัฐกิจ"
   },
   {
    "pos": "CP",
    "name": "ร.อ.เจษฎา"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธราธร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "RO",
    "name": "ร.ต.กันตภณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ยศธน"
   }
  ],
  "tail": "60303",
  "callsign": "CBY401",
  "show": "-",
  "brief": "0945",
  "step": "1000",
  "taxi": "-",
  "to": "1030",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "-/12/51/-",
  "route": "บน.6 - บน.5 - หัวหิน - บน.41 - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "รับ-ส่ง จนท.ฝูง.411",
  "head": "",
  "poc": "ร.อ.ปราณนต์ บุตรเจริญไพศาล",
  "pocTel": "09 7290 2703",
  "remark": "วิ่งขึ้นหลังเสร็จภารกิจ บ.สำรอง รับ รมว.กห.",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-10",
  "tail": null,
  "callsign": "CBY04",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ถานุพงษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.นัฐพณ"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-11",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.วิทวัส"
   },
   {
    "pos": "IP",
    "name": "น.ท.สุทธิรัตน์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ฤทธิเดช"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิติพจน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.บุญลือ"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.ธนชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฎิหาริย์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.พจน์สุวัฒน์"
   }
  ],
  "tail": "60303",
  "callsign": "CBY01",
  "show": "-",
  "brief": "0545",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "STBY",
  "catering": "ใช้จาก บ.จริง",
  "pax": "25",
  "route": "บน.6 - บน.1(0930) - บน.4(1230) - รร.การบิน(1445) - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "บ.สำรอง รับ-ส่ง ผบ.ทอ.และคณะฯ",
  "head": "พล.อ.อ.เสกสรร คันธา",
  "poc": "น.ท.สุรเมธ อินทนิล",
  "pocTel": "08 6353 0007",
  "remark": "บ.จริง A320 บรีฟ 0530 วิ่งขึ้น 0700",
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-11",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.อนันต์ชัย (ฝฟค.2)"
   },
   {
    "pos": "IP",
    "name": "น.ต.ธนะภัทร์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.วีระพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ถานุพงษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง ธิติกุล"
   }
  ],
  "tail": "60316",
  "callsign": "CBY21",
  "show": "-",
  "brief": "0715",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "4 T",
  "catering": "1 ขา",
  "pax": "-/-/20",
  "route": "บน.6 - บน.46 - บน.41(1045) - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "รับ คณะกรรมการตรวจรับเรดาร์",
  "head": "พล.อ.อ.ชาตินนท์ สท้านผไท",
  "poc": "น.อ.ชัยรัตน์ ทองประไพ",
  "pocTel": "06 2818 8032",
  "remark": "ฝึกบินก่อนปฏิบัติภารกิจ",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-11",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ท.ปรัฒสดางค์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ตรัย"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อมรเทพ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.พงศ์ณภัทร์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ศรายุทธ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.วัลลภ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.นัฐพณ"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณัฐชา"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิกา"
   }
  ],
  "tail": "60302",
  "callsign": "CBY412",
  "show": "-",
  "brief": "1045",
  "step": "1100",
  "taxi": "-",
  "to": "1130",
  "fuel": "3 T",
  "catering": "1 ขา",
  "pax": "-/26",
  "route": "บน.6 - หัวหิน(1300) - บน.6",
  "out": "N16",
  "in": "RTAF",
  "name": "รับ ผช.ผบ.ทอ.(กษ.) และ คณก.บริหารการชดเชยการนำเข้ายุทโธปกรณ์ของ ทอ.",
  "head": "พล.อ.อ.ประภาส สอนใจดี",
  "poc": "น.ท.รวินท์ พินิจจันทร์",
  "pocTel": "08 6365 8115",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-11",
  "tail": null,
  "callsign": "CBY101",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนัช"
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
    "name": "พ.อ.ท.ชาติชาย"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ชเนรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-12",
  "tail": null,
  "callsign": "CBY311",
  "name": "STBY ATR72-600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนบัตร"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ชยพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อมรเทพ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.ธนชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-13",
  "tail": null,
  "callsign": "CBY201",
  "name": "STBY ATR72-600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "ร.ท.วสุพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธนดล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อรชุน"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นฤชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-14",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
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
    "name": "พ.อ.อ.อรชุน"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชาติชาย"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.สัมพันธ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนทวัฒน์"
   }
  ],
  "tail": "60302",
  "callsign": "CBY04",
  "show": "-",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "3 T",
  "catering": "-",
  "pax": "34",
  "route": "บน.6 - บน.5 - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "ฝึกบิน",
  "head": "",
  "poc": "",
  "pocTel": "",
  "remark": "ส่ง ข้าราชการเกษียณและบุคคลดีเด่น บน.6",
  "kind_fixed": "",
  "fallback": "training"
 },
 {
  "date": "2026-09-14",
  "crew": [
   {
    "pos": "IP",
    "name": "น.อ.ฉัตฤกษ์"
   },
   {
    "pos": "IP",
    "name": "น.ท.สุทธิรัตน์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ฤทธิเดช"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎา"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.ธนภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ชเนรินทร์"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณิชชารีย์"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง ชัชฎาพร"
   }
  ],
  "tail": "60303",
  "callsign": "CBY601",
  "show": "-",
  "brief": "0800",
  "step": "0830",
  "taxi": "-",
  "to": "0900",
  "fuel": "3.5 T",
  "catering": "1 ขา",
  "pax": "35",
  "route": "บน.6 - บน.41 -บน.6",
  "out": "N14",
  "in": "N14",
  "name": "ส่ง จก.ยก.ทอ.และคณะบริหารโครงการจัดหาเครื่องบินโจมตีเบา",
  "head": "พล.อ.ท.นิทัศน์ ยูประพัฒน์",
  "poc": "น.ท.ธิติ สุขย้อย",
  "pocTel": "09 3424 9399",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-14",
  "tail": null,
  "callsign": "CBY301",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ธนกร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อุดม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นฤชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-15",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ศรราม"
   },
   {
    "pos": "P",
    "name": "ร.อ.ฐาธิปัตย์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "LM",
    "name": "จ.อ.พจน์สุวัฒน์"
   }
  ],
  "tail": "60316",
  "callsign": "CBY201",
  "show": "-",
  "brief": "0515",
  "step": "0530",
  "taxi": "-",
  "to": "0600",
  "fuel": "4.5 T",
  "catering": "-",
  "pax": "-/20/10",
  "route": "บน.6 - บน.56(0900) - ภูเก็ต - บน.6",
  "out": "N15",
  "in": "N15",
  "name": "รับ-ส่ง รอง จก.จร.ทอ.และคณะตรวจการปฏิบัติราชการ",
  "head": "น.อ.ศักดิ์สิทธิ์ เจริญพจน์",
  "poc": "น.อ.มนธร เด่นดวง",
  "pocTel": "09 3323 9351",
  "remark": "บน.56 รับ รอง ผบ.ศขฝล.คปอ.และคณะฯ (10 คน) กลับ บน.6",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-15",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "P",
    "name": "น.ต.ธนกร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ไกรรัฐ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รังสิมันตุ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อุดม"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.กิตติภัฏ"
   }
  ],
  "tail": "60303",
  "callsign": "CBY101",
  "show": "-",
  "brief": "0615",
  "step": "0630",
  "taxi": "-",
  "to": "0700",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-/32",
  "route": "บน.6 - บน.5 - บน.6",
  "out": "N15",
  "in": "RTAF2",
  "name": "ฝึกบิน",
  "head": "",
  "poc": "",
  "pocTel": "",
  "remark": "",
  "kind_fixed": "",
  "fallback": "training"
 },
 {
  "date": "2026-09-15",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธนดล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วนิดา"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ณัฐณิชา"
   }
  ],
  "tail": "60313",
  "callsign": "CBY05",
  "show": "-",
  "brief": "1000",
  "step": "1030",
  "taxi": "-",
  "to": "1100",
  "fuel": "3 T",
  "catering": "2 ขา",
  "pax": "15",
  "route": "บน.6 - บน.1(1600) - บน.6",
  "out": "N14",
  "in": "N14",
  "name": "รับ-ส่ง ราชองครักษ์ประจำพระองค์ และคณะ สนภ.ทอ.",
  "head": "พล.อ.ท.โชคดี สมจิตต์",
  "poc": "น.อ.เสือ ลือนาม",
  "pocTel": "09 7965 2895",
  "remark": "",
  "kind_fixed": "",
  "fallback": "rtaf"
 },
 {
  "date": "2026-09-15",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนะภัทร์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.วรพงษ์"
   },
   {
    "pos": "N",
    "name": "ร.ท.ชยพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.พงษ์พิพัฒน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ปวีณ์กร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นฤชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.วัลลภ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ยศธน"
   }
  ],
  "tail": "60303",
  "callsign": "CBY77",
  "show": "-",
  "brief": "1330",
  "step": "STBY",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3.5 T",
  "catering": "ใช้จาก บ.จริง",
  "pax": "1+26",
  "route": "บน.6(พร้อม 1400) - ร้อยเอ็ด - บน.6",
  "out": "N16",
  "in": "N16",
  "name": "บ.ที่นั่งสำรอง รับ-ส่ง และ บ.เตรียมพร้อมลำเลียงสายแพทย์ทางอากาศ เจ้าจอม พล.ท.หญิง ท่านผู้หญิงอรอนงค์ ปิยนาฏวชิรพัทธ์",
  "head": "",
  "poc": "พ.อ.อิทธิพล นามภูงา",
  "pocTel": "08 6351 9192",
  "remark": "การแต่งกายชุดแขนยาวบ่าอ่อน · น.เอกสาร: ร.ท.ชยพล ไวยเนตร 08 6994 7990",
  "kind_fixed": "stby",
  "fallback": "stby"
 },
 {
  "date": "2026-09-15",
  "tail": null,
  "callsign": "CBY401",
  "name": "STBY ATR72-500/600",
  "show": "",
  "brief": "",
  "step": "STBY",
  "taxi": "",
  "to": "STBY",
  "fuel": "",
  "catering": "",
  "pax": "",
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
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.วีระพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธราธร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิรวัฒน์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นิรวิทธ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนทวัฒน์"
   }
  ],
  "kind_fixed": "stby",
  "fallback": "stby"
 }
]$json$::jsonb) with ordinality as t(x, n)
 order by n;

-- ---------- สรุป ----------
select count(*) as "ภารกิจ ก.ย. ในระบบ",
       count(*) filter (where kind = 'stby') as "STBY"
  from public.missions where mission_date between '2026-09-01' and '2026-09-30';
