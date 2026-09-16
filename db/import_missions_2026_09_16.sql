-- =====================================================================
--  Flight Operation · import_missions_2026_09_16.sql
--  ภารกิจวันพุธที่ 16 ก.ย. 2569 (จากกระดานจัดบิน) — 3 ภารกิจ + ชุด STBY
--  • ต้องรัน catchup_2026_09_14.sql และ seed_pilots.sql ก่อน
--  • รันซ้ำได้: ภารกิจที่มี วันที่ + COWBOY + T/O ตรงกันอยู่แล้วจะถูกข้าม
--  • ชนิดภารกิจตั้งเป็น "ภารกิจ ทอ." (กระดานไม่มีสี) — เปลี่ยนได้ที่ปุ่มแก้ไขในหน้าภารกิจ
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
  -- ชื่อเดิม (migration_15) — ถ้ายังไม่ได้รันจะข้ามขั้นนี้
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

select x->>'callsign' as "COWBOY", x->>'to' as "T/O", left(x->>'name', 45) as "ภารกิจ",
       pg_temp.add_mission(x) as "ผล"
  from jsonb_array_elements($json$[
 {
  "date": "2026-09-16",
  "tail": "60303",
  "callsign": "CBY401",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "4.8 T",
  "catering": "2 ขา",
  "pax": "36/27/16/-/25",
  "name": "รับ-ส่ง ราชองครักษ์ และคณะสำรวจพื้นที่เตรียมการเสด็จ 905",
  "route": "บน.6 - บน.56 - บอทอง - นราธิวาส - บน.56(1300) - บน.6",
  "head": "พล.ท.กษิดิ์เดช วัฒนวรางกูร",
  "poc": "พ.ต.ขนาธิป ผลปราชญ์",
  "pocTel": "08 0435 5971",
  "out": "N16",
  "in": "N16",
  "remark": "",
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
    "name": "ร.อ.ณภัทร"
   },
   {
    "pos": "CP",
    "name": "ร.อ.มหินทรา"
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
    "name": "จ.อ.ธีรศักดิ์"
   },
   {
    "pos": "LM",
    "name": "ร.ท.ศักรินทร์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณัฐวรียา"
   },
   {
    "pos": "AH",
    "name": "จ.อ.หญิง พีชานิภา"
   }
  ]
 },
 {
  "date": "2026-09-16",
  "tail": "60316",
  "callsign": "CBY04",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0715",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "4 T",
  "catering": "2 ขา",
  "pax": "26/10",
  "name": "(1) ส่ง ปช.ทอ. และคณะฯ / (2) รับ รอง เสธ.คปอ. และคณะฯ",
  "route": "บน.6 - บน.41(1030) - บน.6",
  "head": "(1) พล.อ.ท.อิทธิกร พงศ์อัจฉริย์ / (2) พล.อ.ต.อนุกูล อ่อนจันทร์อ่อม",
  "poc": "(1) น.อ.ธีร์ ธนัตถ์ศรุต 09 5595 9441 / (2) น.อ.สุรพงศ์ ชูรส 08 9524 0258",
  "pocTel": "",
  "out": "N14",
  "in": "N14",
  "remark": "",
  "crew": [
   {
    "pos": "P",
    "name": "น.ต.ธนากร"
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
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ปฏิภาณ"
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
    "name": "จ.ท.หญิง ณัฐชา"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง วิภารัตน์"
   }
  ]
 },
 {
  "date": "2026-09-16",
  "tail": "60313",
  "callsign": "CBY201",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0730",
  "step": "0800",
  "taxi": "-",
  "to": "0830",
  "fuel": "3 T",
  "catering": "2 ขา",
  "pax": "15",
  "name": "รับ-ส่ง ราชองครักษ์ประจำพระองค์ และคณะ สนภ.ทอ.",
  "route": "บน.6 - บน.4(1530) - บน.6",
  "head": "พล.อ.ท.โชคดี สมจิตต์",
  "poc": "น.อ.เสือ ลือนาม",
  "pocTel": "09 7965 2895",
  "out": "N15",
  "in": "N15",
  "remark": "",
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
    "name": "พ.อ.อ.อมรเทพ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ท.ชลันธร"
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
    "name": "พ.อ.อ.ทินวัฒน์"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณัฐชา"
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง วนิดา"
   }
  ]
 },
 {
  "date": "2026-09-16",
  "tail": null,
  "callsign": "CBY301",
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
    "name": "น.ต.ธนกร"
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
    "name": "พ.อ.ต.พงศ์ณภัทร"
   },
   {
    "pos": "RO",
    "name": "พ.อ.ต.ก้องกิดากร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.กิตติภัฏ"
   }
  ]
 }
]$json$::jsonb) with ordinality as t(x, n)
 order by n;

select count(*) as "ภารกิจ 16 ก.ย." from public.missions where mission_date = '2026-09-16';
