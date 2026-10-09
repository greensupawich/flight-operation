-- =====================================================================
--  Flight Operation · import_missions_2026_10_09.sql
--  ภารกิจวันศุกร์ที่ 9 ต.ค. 2569 (จากกระดานจัดบิน) — 3 ภารกิจ + ชุด STBY
--  • ต้องรัน catchup_2026_09_14.sql, seed_pilots.sql และ migration_20_day_notes.sql ก่อน
--  • รันซ้ำได้: ภารกิจที่มี วันที่ + COWBOY + T/O ตรงกันอยู่แล้วจะถูกข้าม
--  • น.จัดบิน: 09 = ร.อ.ยุทธพล · 10 = ร.อ.สตภัทร
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

select x->>'callsign' as "COWBOY", x->>'to' as "T/O", left(x->>'name', 45) as "ภารกิจ",
       pg_temp.add_mission(x) as "ผล"
  from jsonb_array_elements($json$[
 {
  "date": "2026-10-09",
  "tail": "60316",
  "callsign": "CBY101",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0615",
  "step": "0630",
  "taxi": "-",
  "to": "0700",
  "fuel": "4 T",
  "catering": "1 ขา",
  "pax": "-/15",
  "name": "รับ ผทค.พิเศษ ทอ.และ คณก.บริหารโครงการพัฒนาระบบป้องกันทางอากาศ",
  "route": "บน.6 - ภูเก็ต(0930) - บน.6",
  "head": "พล.อ.อ.วิเชียร วิเชียรธรรม",
  "poc": "ร.ท.หญิง จนิลญา ดาวี",
  "pocTel": "08 0496 6109",
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
    "name": "น.ต.พงศ์วิสิฐ"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ภวิล"
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
    "name": "พ.อ.ท.พงศกร"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.เกียรติสกุล"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ปาฏิหาริย์"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง วารินาถ"
   },
   {
    "pos": "AH",
    "name": "จ.ท.หญิง ณัชชา"
   }
  ]
 },
 {
  "date": "2026-10-09",
  "tail": "60302",
  "callsign": "CBY201",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0700",
  "step": "0730",
  "taxi": "-",
  "to": "0800",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "27/-/30/-",
  "name": "(1) ส่ง กำลังพล ศปก.อย. ที่ บน.56 / (2) รับ-ส่ง จนท.ฝูง.201 พร้อมอุปกรณ์ จาก บน.7 ไปส่งที่ บน.2",
  "route": "บน.6 - บน.56 - บน.7(1230) - บน.2 - บน.6",
  "head": "",
  "poc": "(1) น.ท.กาญจน์ อึกจอมทอง 08 4005 0939 / (2) น.ต.พัฒนพงษ์ พรหมพันธ์ 08 2799 2736",
  "pocTel": "",
  "out": "N15",
  "in": "N15",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.ต.ธนบัตร"
   },
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
    "name": "ร.อ.พฤกษ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.จิรายุทธ์"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.รังสิมันต์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.นิรวิทธ์"
   },
   {
    "pos": "RO",
    "name": "จ.อ.ภูธเนศ"
   },
   {
    "pos": "LM",
    "name": "พ.อ.อ.ชาญศักดิ์"
   },
   {
    "pos": "LM",
    "name": "จ.อ.รณกฤต"
   }
  ]
 },
 {
  "date": "2026-10-09",
  "tail": "60303",
  "callsign": "CBY113",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0800",
  "step": "0830",
  "taxi": "-",
  "to": "0900",
  "fuel": "3 T",
  "catering": "1 ขา",
  "pax": "44/21/37",
  "name": "(1) บ.เมล์สายเหนือ บน.41, บน.46 / (2) รับ เสธ.คปอ.และ คณก.บริหารโครงการพัฒนาระบบป้องกันทางอากาศ",
  "route": "บน.6 - บน.41 - บน.46(1430) - บน.6",
  "head": "(2) พล.อ.ท.อานนท์ จารุสมบัติ",
  "poc": "(2) น.อ.จตุวิทย ปัญญาไว",
  "pocTel": "08 9944 3946",
  "out": "N16",
  "in": "N16",
  "remark": "",
  "crew": [
   {
    "pos": "IP",
    "name": "น.อ.เอกราช"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ยุทธพล"
   },
   {
    "pos": "CP",
    "name": "ร.อ.มหินทรา"
   },
   {
    "pos": "CP",
    "name": "ร.อ.ณภัทร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.เจษฎากร"
   },
   {
    "pos": "FM",
    "name": "พ.อ.ต.ธนภัทร"
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
   },
   {
    "pos": "AH",
    "name": "พ.อ.อ.หญิง ณิชชารีย์"
   },
   {
    "pos": "AH",
    "name": "จ.ต.หญิง วิภารัตน์"
   }
  ]
 },
 {
  "date": "2026-10-09",
  "tail": null,
  "callsign": "CBY401",
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
  "name": "STBY ATR72-600",
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
    "name": "ร.ท.ตรัย"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.ศตวรรษ"
   },
   {
    "pos": "FM",
    "name": "พ.อ.อ.วชิรวัฒน์"
   },
   {
    "pos": "RO",
    "name": "พ.อ.อ.สัมพันธ์"
   },
   {
    "pos": "LM",
    "name": "พ.อ.ท.ปราชชัยญา"
   }
  ]
 }
]$json$::jsonb) with ordinality as t(x, n)
 order by n;

-- น.จัดบินภารกิจ (วันนี้ + วันถัดไป)
insert into public.day_notes (log_date, duty_officer, duty_phone, updated_at) values
  ('2026-10-09', 'ร.อ.ยุทธพล', '08 9919 9065', now()),
  ('2026-10-10', 'ร.อ.สตภัทร', '09 8514 4688', now())
on conflict (log_date) do update
  set duty_officer = excluded.duty_officer, duty_phone = excluded.duty_phone, updated_at = now();

select count(*) as "ภารกิจ 2026-10-09" from public.missions where mission_date = '2026-10-09';
