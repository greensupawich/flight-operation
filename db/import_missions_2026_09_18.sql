-- =====================================================================
--  Flight Operation · import_missions_2026_09_18.sql
--  ภารกิจวันศุกร์ที่ 18 ก.ย. 2569 (จากกระดานจัดบิน) — 2 ภารกิจ + ชุด STBY
--  • ต้องรัน catchup_2026_09_14.sql, seed_pilots.sql และ migration_20_day_notes.sql ก่อน
--  • รันซ้ำได้: ภารกิจที่มี วันที่ + COWBOY + T/O ตรงกันอยู่แล้วจะถูกข้าม
--  • น.จัดบิน: วันนี้ (18) = ร.อ.บัณฑิต · พรุ่งนี้ (19) = ร.อ.ยุทธพล
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
  "date": "2026-09-18",
  "tail": "60303",
  "callsign": "CBY05",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0600",
  "step": "0610",
  "taxi": "0620",
  "to": "0730",
  "fuel": "3.5 T",
  "catering": "2 ขา",
  "pax": "3/10",
  "name": "รับ-ส่ง องคมนตรี และคณะฯ",
  "route": "บน.6 - บน.41(รอรับ/1400) - บน.6",
  "head": "นายเกษม วัฒนชัย",
  "poc": "นายสรรเสริญ สาโรวาท",
  "pocTel": "08 1845 7585",
  "out": "RTAF2",
  "in": "RTAF2",
  "remark": "",
  "crew": [
   { "pos": "P", "name": "ร.อ.นฤดล" },
   { "pos": "CP", "name": "ร.ท.ตรัย" },
   { "pos": "FM", "name": "พ.อ.อ.ศตวรรษ" },
   { "pos": "FM", "name": "พ.อ.อ.เจษฎากร" },
   { "pos": "RO", "name": "พ.อ.ท.ธนชิต" },
   { "pos": "LM", "name": "ร.ท.ศักรินทร์" },
   { "pos": "LM", "name": "จ.อ.นนทวัฒน์" },
   { "pos": "AH", "name": "จ.อ.หญิง อิติกุล" },
   { "pos": "AH", "name": "จ.ท.หญิง ชัชฎาพร" }
  ]
 },
 {
  "date": "2026-09-18",
  "tail": "60316",
  "callsign": "CBY201",
  "kind_fixed": "",
  "fallback": "rtaf",
  "show": "-",
  "brief": "0745",
  "step": "0800",
  "taxi": "-",
  "to": "0830",
  "fuel": "3.5 T",
  "catering": "-",
  "pax": "-/15",
  "name": "รับ จนท.ฝูง.211 สนับสนุนหน่วยบินเดโชชัย",
  "route": "บน.6 - บน.21 - บน.6",
  "head": "",
  "poc": "ร.อ.กิติพัฒน์ จันทวีโรจน์",
  "pocTel": "06 5565 2656",
  "out": "N14",
  "in": "N14",
  "remark": "",
  "crew": [
   { "pos": "IP", "name": "น.ต.ศรราม" },
   { "pos": "CP", "name": "ร.อ.บัณฑิต" },
   { "pos": "FM", "name": "พ.อ.อ.พงษ์พิพัฒน์" },
   { "pos": "FM", "name": "พ.อ.ต.ปวีณกร" },
   { "pos": "RO", "name": "จ.อ.ธีรศักดิ์" },
   { "pos": "LM", "name": "พ.อ.อ.ทินวัฒน์" },
   { "pos": "LM", "name": "พ.อ.อ.กิตติภัฏ" }
  ]
 },
 {
  "date": "2026-09-18",
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
  "name": "STBY ATR72-500/600",
  "route": "",
  "head": "",
  "poc": "",
  "pocTel": "",
  "out": "",
  "in": "",
  "remark": "",
  "crew": [
   { "pos": "IP", "name": "น.ต.ณัฐดนัย" },
   { "pos": "CP", "name": "ร.อ.ณัฐกิจ" },
   { "pos": "FM", "name": "พ.อ.อ.รังสิมันต์" },
   { "pos": "FM", "name": "พ.อ.อ.วชิรวัฒน์" },
   { "pos": "RO", "name": "พ.อ.อ.ชเนรินทร์" },
   { "pos": "LM", "name": "จ.อ.รณกฤต" }
  ]
 }
]$json$::jsonb) with ordinality as t(x, n)
 order by n;

-- น.จัดบินภารกิจ: วันนี้ (18) = ร.อ.บัณฑิต · พรุ่งนี้ (19) = ร.อ.ยุทธพล
insert into public.day_notes (log_date, duty_officer, duty_phone, updated_at) values
  ('2026-09-18', 'ร.อ.บัณฑิต', '09 4404 4884', now()),
  ('2026-09-19', 'ร.อ.ยุทธพล', '08 9919 9065', now())
on conflict (log_date) do update
  set duty_officer = excluded.duty_officer, duty_phone = excluded.duty_phone, updated_at = now();

select count(*) as "ภารกิจ 18 ก.ย." from public.missions where mission_date = '2026-09-18';
