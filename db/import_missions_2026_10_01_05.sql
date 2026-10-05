-- =====================================================================
--  Flight Operation · import_missions_2026_10_01_05.sql
--  ภารกิจ 1–5 ต.ค. 2569 จากไฟล์ "จัดบิน ฝูง.603 3-5 ต.ค.69 แก้ไขครั้งที่ 2.xlsx" (ชีตละวัน)
--  • ต้องรัน migration_27 (ชนิด stby_dechochai) ก่อน
--  • การ์ด "STBY DEPLOY" (BRIEF/T/O = STBY) → ชนิด STBY เดโชชัย (stby_dechochai)
--    ถ้าถูกเรียกใช้ ให้แก้ภารกิจเปลี่ยนเป็น "เดโชชัย" เอง
--  • กล่อง STBY ซ้ายล่าง → ชนิด STBY · ชื่อใต้กล่อง STBY = น.จัดบินของวันนั้น
--  • ชนิดภารกิจ: ชื่อ "ฝึกบิน" / "บ.พระที่นั่ง·ถวายงาน" กำหนดตายตัว · อื่น ๆ ใช้สีในคิวบิน → ถ้าไม่มี = ภารกิจ ทอ.
--  • รันซ้ำได้: ภารกิจที่มี วันที่ + COWBOY + T/O ตรงกันอยู่แล้วจะถูกข้าม
--    (ถ้าเคยกรอกวันเหล่านี้ในเว็บแล้ว และเวลา T/O ต่างจากไฟล์ จะได้ภารกิจซ้ำ — ดูตารางท้ายไฟล์)
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
  "date": "2026-10-01",
  "tail": "60303",
  "callsign": "CBY201",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0815",
  "step": "0830",
  "taxi": "-",
  "to": "0900",
  "fuel": "2.5 T",
  "catering": "-",
  "pax": "-",
  "name": "ผลัดเปลี่ยนกำลังพล",
  "route": "บน.4 - บน.6",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "ค้างคืน",
  "in": "N15",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภานุวัฒน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.พงศ์ณภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.สัมพันธ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.นัฐพณ"
   }
  ]
 },
 {
  "date": "2026-10-01",
  "tail": "60316",
  "callsign": "CBY401",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0800",
  "step": "0810",
  "taxi": "0820",
  "to": "0930",
  "fuel": "3.5 T",
  "catering": "1 ขา",
  "pax": "24/21",
  "name": "ส่ง เสธ.ทอ.และคณะฯ",
  "route": "บน.6 - บน.7(1500) - บน.6",
  "head": "",
  "poc": "น.ต.เมธี จิตต์ชุ่ม",
  "pocTel": "09 4959 5365",
  "out": "RTAF2",
  "in": "N15",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รังสิมันตุ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ปวีณ์กร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ต.ก้องกิดากร"
   },
   {
    "pos": "LM",
    "name": "ร.ท.สมพร"
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
    "name": "พ.อ.อ.หญิง วราภรณ์ ธ."
   }
  ]
 },
 {
  "date": "2026-10-01",
  "tail": "60302",
  "callsign": "CBY777",
  "kind_fixed": "palace",
  "fallback": "palace",
  "show": "-",
  "brief": "1700",
  "step": "1910",
  "taxi": "1920",
  "to": "2130",
  "fuel": "3.5 T",
  "catering": "1 ขา",
  "pax": "34/5",
  "name": "บ.พระที่นั่ง ส่ง 911 พร้อมผู้ตามเสด็จ",
  "route": "บก.ทอ. - บน.41 - บน.6",
  "head": "น.อ.พรประเสริฐ ผ่านภพ 08 1639 4461",
  "poc": "ร.อ.ศุภวิชญ์",
  "pocTel": "08 6505 2961",
  "out": "บก.ทอ.",
  "in": "N16",
  "remark": "การแต่งกายชุดแขนยาวบ่าอ่อน",
  "crew": [
   {
    "pos": "FM",
    "name": "พ.อ.อ.ศตวรรษ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.พงษ์พิพัฒน์"
   },
   {
    "pos": "RO",
    "name": "ร.ต.กันตภณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.วัลลภ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วราภรณ์ บ."
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วนิดา"
   }
  ]
 },
 {
  "date": "2026-10-01",
  "tail": "60303",
  "callsign": "CBY04",
  "kind_fixed": "palace",
  "fallback": "palace",
  "show": "-",
  "brief": "1700",
  "step": "1910",
  "taxi": "1920",
  "to": "2130",
  "fuel": "4 T",
  "catering": "ใช้จาก บ.จริง",
  "pax": "34/5",
  "name": "บ.พระที่นั่งสำรอง ส่ง 911 พร้อมผู้ตามเสด็จ",
  "route": "บก.ทอ. - บน.41 - บน.6",
  "head": "น.อ.พรประเสริฐ ผ่านภพ 08 1639 4461",
  "poc": "ร.ท.จักพงศ์ ศิริโพธิ์",
  "pocTel": "08 1646 3886",
  "out": "บก.ทอ.",
  "in": "N14",
  "remark": "การแต่งกายชุดแขนยาวบ่าอ่อน",
  "crew": [
   {
    "pos": "P",
    "name": "น.ต.ธนากร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ณภัทร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ธราธร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ถานุพงษ์"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   }
  ]
 },
 {
  "date": "2026-10-01",
  "tail": "60313",
  "callsign": "CBY201",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "1245",
  "step": "1300",
  "taxi": "-",
  "to": "1330",
  "fuel": "2.5 T",
  "catering": "-",
  "pax": "-",
  "name": "Re-deploy",
  "route": "บน.4 - บน.6",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "ค้างคืน",
  "in": "N15",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ศรราม"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อรชุน"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.ธนชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   }
  ]
 },
 {
  "date": "2026-10-01",
  "tail": null,
  "callsign": "CBY02",
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
    "name": "น.ต.ธนะภัทร์"
   },
   {
    "pos": "P",
    "name": "ร.อ.วรพงษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.กิตติพศ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิรวัฒน์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ทินวัฒน์"
   }
  ]
 },
 {
  "date": "2026-10-02",
  "tail": "60302",
  "callsign": "CBY401",
  "kind_fixed": "training",
  "fallback": "training",
  "show": "-",
  "brief": "0600",
  "step": "0610",
  "taxi": "0620",
  "to": "0730",
  "fuel": "3.5 T",
  "catering": "2 ขา",
  "pax": "6/10",
  "name": "ฝึกบิน",
  "route": "บน.6 - บน.7(1700) - บน.6",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "RTAF2",
  "in": "RTAF2",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.มหินทรา"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วราภรณ์ ธ."
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ชุติกาญจน์"
   }
  ]
 },
 {
  "date": "2026-10-02",
  "tail": null,
  "callsign": "CBY302",
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
    "name": "ร.อ.ฐาธิปัตย์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.วีระพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อมรเทพ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชาติชาย"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นิรวิทธ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   }
  ]
 },
 {
  "date": "2026-10-03",
  "tail": "60302",
  "callsign": "CBY101",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0900",
  "step": "0910",
  "taxi": "0920",
  "to": "1030",
  "fuel": "3 T",
  "catering": "2 ขา",
  "pax": "22",
  "name": "รับ-ส่ง รมว.กห.และคณะฯ",
  "route": "บน.6 - บน.1(1500) - บน.6",
  "head": "พล.ท.อดุลย์ บุญธรรมเจริญ",
  "poc": "พ.อ.ใหญ่ยิ่ง หาญสุทธิธรรม",
  "pocTel": "08 6718 8881",
  "out": "RTAF2",
  "in": "RTAF2",
  "remark": "ATR72-600/303 เป็น บ.สำรอง",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.ศักย์สรณ์ ไฝขาว"
   },
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "CP",
    "name": "ร.อ.วีระพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.บุญลือ"
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
    "name": "ร.ท.สมพร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.วัลลภ"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง รุ่งทิวา"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง วารินาถ"
   }
  ]
 },
 {
  "date": "2026-10-03",
  "tail": "60313",
  "callsign": "CBY201",
  "kind_fixed": "palace",
  "fallback": "palace",
  "show": "-",
  "brief": "0910",
  "step": "-",
  "taxi": "-",
  "to": "1000",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "15",
  "name": "รับ-ส่ง จนท.ถวายงาน HMSV พร้อมพระราชสัมภาระ",
  "route": "บน.6 - บน.7(รอรับ) - บน.6",
  "head": "",
  "poc": "น.อ.กฤษณะ สุขดี",
  "pocTel": "09 8991 5362",
  "out": "N14",
  "in": "N14",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ศรราม"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิรวัฒน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.ธนภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.ศรายุทธ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนทวัฒน์"
   }
  ]
 },
 {
  "date": "2026-10-03",
  "tail": "60303",
  "callsign": "CBY05",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N15",
  "in": "N15",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ศุภวิชญ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ศตวรรษ"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   }
  ]
 },
 {
  "date": "2026-10-03",
  "tail": "60316",
  "callsign": "CBY302",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N16",
  "in": "N16",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.ฐาธิปัตย์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
   },
   {
    "pos": "FM",
    "name": "ร.อ.บุญส่ง"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นฤชิต"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   }
  ]
 },
 {
  "date": "2026-10-03",
  "tail": null,
  "callsign": "CBY04",
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
    "name": "น.ต.ธนากร"
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
    "name": "พ.อ.อ.กิติพจน์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ต.ก้องกิดากร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   }
  ]
 },
 {
  "date": "2026-10-04",
  "tail": "60302",
  "callsign": "CBY01",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "",
  "brief": "0530",
  "step": "0540",
  "taxi": "0550",
  "to": "0700",
  "fuel": "3.5 T",
  "catering": "2 ขา",
  "pax": "20",
  "name": "รับ-ส่ง ผบ.ทอ.และคณะฯ",
  "route": "บน.6 - บน.7(รอรับ) - บน.6",
  "head": "​พล.อ.อ.เสกสรร คันธา",
  "poc": "น.อ.กฤษฎา",
  "pocTel": "08 7821 7246",
  "out": "RTAF2",
  "in": "RTAF2",
  "remark": "ATR72-600/303 เป็น บ.สำรอง",
  "crew": [
   {
    "pos": "AC",
    "name": "น.อ.ฉัตฤกษ์ ป้องกันภัย"
   },
   {
    "pos": "IP",
    "name": "น.ท.ปรัฒสดางค์"
   },
   {
    "pos": "IP",
    "name": "น.ต.ธนบัตร"
   },
   {
    "pos": "CP",
    "name": "ร.ท.มหินทรา"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
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
    "name": "พ.อ.อ.วัลลภ"
   },
   {
    "pos": "LM",
    "name": "จ.อ.พจน์สุวัฒน์"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วราภรณ์ ธ"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณัฐชา"
   }
  ]
 },
 {
  "date": "2026-10-04",
  "tail": "60303",
  "callsign": "CBY401",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N15",
  "in": "N15",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ณัฐดนัย"
   },
   {
    "pos": "CP",
    "name": "ร.อ.พฤกษ์"
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
    "name": "พ.อ.อ.ทินวัฒน์"
   }
  ]
 },
 {
  "date": "2026-10-04",
  "tail": "60313",
  "callsign": "CBY101",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N14",
  "in": "N14",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนัช"
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
    "pos": "RO",
    "name": "พ.อ.ท.ธนชิต"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   }
  ]
 },
 {
  "date": "2026-10-04",
  "tail": "60316",
  "callsign": "CBY05",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N16",
  "in": "N16",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ณัฐกิจ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รณชัย"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.วินัย"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   }
  ]
 },
 {
  "date": "2026-10-04",
  "tail": null,
  "callsign": "CBY302",
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
    "name": "ร.อ.ฐาธิปัตย์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิรวัฒน์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ปวีณ์กร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.อัครวิทย์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.กิตติภัฏ"
   }
  ]
 },
 {
  "date": "2026-10-05",
  "tail": "60303",
  "callsign": "CBY06",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0815",
  "step": "-",
  "taxi": "-",
  "to": "0900",
  "fuel": "4 T",
  "catering": "-",
  "pax": "25",
  "name": "รับ-ส่ง จนท.ฝูง.201 พร้อมสัมภาระ",
  "route": "บน.6 - บน.2 - บน.56 - บน.6",
  "head": "",
  "poc": "น.ต.เชษฐ์สกุล ยศพลสิทธิ์",
  "pocTel": "06 3084 0887",
  "out": "N14",
  "in": "N14",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.วรพงษ์"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภานุวัฒน์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.วสุพล"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.อมรเทพ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นิรวิทธ์"
   },
   {
    "pos": "LM",
    "name": "ร.ท.สมพร"
   },
   {
    "pos": "LM",
    "name": "จ.อ.นนทวัฒน์"
   }
  ]
 },
 {
  "date": "2026-10-05",
  "tail": "60302",
  "callsign": "CBY302",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N15",
  "in": "N15",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.ฐาธิปัตย์"
   },
   {
    "pos": "CP",
    "name": "ร.ท.ฤทธิเดช"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ปวีณ์กร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.นัฐพณ"
   }
  ]
 },
 {
  "date": "2026-10-05",
  "tail": "60313",
  "callsign": "CBY301",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N14",
  "in": "N14",
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
    "name": "พ.อ.อ.พงษ์พิพัฒน์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.สัมพันธ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.อัฐพล"
   }
  ]
 },
 {
  "date": "2026-10-05",
  "tail": "60316",
  "callsign": "CBY05",
  "kind_fixed": "stby_dechochai",
  "fallback": "stby_dechochai",
  "show": "-",
  "brief": "STBY",
  "step": "-",
  "taxi": "-",
  "to": "STBY",
  "fuel": "3 T",
  "catering": "-",
  "pax": "-",
  "name": "STBY DEPLOY",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "N16",
  "in": "N16",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "ร.อ.นฤดล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.บัณฑิต"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.ธนภัทร"
   },
   {
    "pos": "RO",
    "name": "ร.ท.คุณากร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   }
  ]
 },
 {
  "date": "2026-10-05",
  "tail": null,
  "callsign": "CBY101",
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
    "name": "น.ต.ธนัช"
   },
   {
    "pos": "CP",
    "name": "ร.อ.กิตติคม"
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
    "name": "พ.อ.อ.ศรายุทธ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   }
  ]
 }
]$json$::jsonb) with ordinality as t(x, n)
 order by n;

-- น.จัดบินภารกิจ รายวัน (ชื่อใต้กล่อง STBY ของแต่ละวัน + วันถัดไปจากท้ายชีต 5 ต.ค.)
insert into public.day_notes (log_date, duty_officer, duty_phone, updated_at) values
  ('2026-10-01', 'ร.อ.บัณฑิต', '09 4404 4884', now()),
  ('2026-10-02', 'ร.อ.บัณฑิต', '09 4404 4884', now()),
  ('2026-10-03', 'ร.อ.ภานุวัฒน์', '09 5679 9684', now()),
  ('2026-10-04', 'ร.อ.ภานุวัฒน์', '09 5679 9684', now()),
  ('2026-10-05', 'ร.อ.ภานุวัฒน์', '09 5679 9684', now()),
  ('2026-10-06', 'ร.อ.วีระพล', '08 2468 0635', now())
on conflict (log_date) do update
  set duty_officer = excluded.duty_officer, duty_phone = excluded.duty_phone, updated_at = now();

-- ตรวจผล: ภารกิจทั้งหมด 1–5 ต.ค. (ดูว่ามีซ้ำไหม)
select m.mission_date as "วันที่", m.callsign as "COWBOY", m.takeoff_time as "T/O", m.kind as "ชนิด",
       a.tail_number as "เครื่อง", left(m.mission_name, 40) as "ภารกิจ"
  from public.missions m left join public.aircraft a on a.id = m.aircraft_id
 where m.mission_date between '2026-10-01' and '2026-10-05'
 order by m.mission_date, m.callsign, m.takeoff_time;
