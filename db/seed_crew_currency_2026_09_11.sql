-- =====================================================================
--  Flight Operation · seed_crew_currency_2026_09_11.sql
--  ข้อมูลความพร้อมบิน (currency) ตั้งต้น ตามตาราง "อัพเดท 11 ก.ย.69"
--   • ช่องดำในภาพ = บินแบบนั้นไม่ได้ (q5/q6 = false)
--   • "ขาด" = ไม่มีวันบินล่าสุด (null)
--   • ปี 68 = พ.ศ.2568 (2025) · ปี 69 = พ.ศ.2569 (2026)
--  ต้องรัน migration_21 ก่อน · จับคู่นักบินด้วยชื่อ (ตัดช่องว่าง) + ชื่อเดิม + ชื่อล้วน (ถ้าไม่ซ้ำ)
--  ท้ายไฟล์: ดันวันบินล่าสุดให้ทันสมัยจากรายงานหลังบินจริง (รวมเที่ยวบินล่าสุด)
--  รันใน Supabase → SQL Editor · รันซ้ำได้
-- =====================================================================
create or replace function pg_temp.set_cur(p_name text, p_d500 date, p_d600 date, p_q500 boolean, p_q600 boolean)
returns text language plpgsql as $$
declare v_clean text; v_bare text; v_id uuid; n int;
begin
  v_clean := regexp_replace(coalesce(p_name,''),'\s','','g');
  select id into v_id from public.crew_members where regexp_replace(full_name,'\s','','g')=v_clean limit 1;
  if v_id is null and to_regclass('public.crew_aliases') is not null then
    execute 'select crew_member_id from public.crew_aliases where alias=$1' into v_id using v_clean;
  end if;
  if v_id is null then
    v_bare := regexp_replace(v_clean,'^([^.]{1,3}\.)+','');
    select count(*), min(id::text)::uuid into n,v_id from public.crew_members
      where regexp_replace(regexp_replace(full_name,'\s','','g'),'^([^.]{1,3}\.)+','')=v_bare;
    if n<>1 then v_id := null; end if;
  end if;
  if v_id is null then return '✗ ไม่พบ/ชื่อซ้ำ'; end if;
  update public.crew_members
     set last_500_date=p_d500, last_600_date=p_d600, can_fly_500=p_q500, can_fly_600=p_q600
   where id=v_id;
  return '✓ อัปเดต';
end $$;

select x->>'n' as "นักบิน", pg_temp.set_cur(
         x->>'n', nullif(x->>'d5','')::date, nullif(x->>'d6','')::date,
         (x->>'q5')::boolean, (x->>'q6')::boolean) as "ผล"
from jsonb_array_elements($json$[
 {"n":"น.อ.ฉัตฤกษ์",      "d5":"2026-07-14","d6":"2026-07-27","q5":true,"q6":true},
 {"n":"น.อ.ชญานิน",       "d5":"2026-08-14","d6":"2026-09-04","q5":true,"q6":true},
 {"n":"น.อ.บุญธรัฐ",      "d5":"2026-07-20","d6":"2026-08-06","q5":true,"q6":true},
 {"n":"น.อ.จิราพงษ์",     "d5":"2025-06-27","d6":"2026-05-19","q5":true,"q6":true},
 {"n":"น.อ.เอกราช",       "d5":"2025-02-10","d6":"2026-08-03","q5":true,"q6":true},
 {"n":"น.ท.วรุตม์",       "d5":"",          "d6":"2026-09-07","q5":true,"q6":true},
 {"n":"น.ท.สกุลกอ",       "d5":"2025-08-08","d6":"2025-08-21","q5":true,"q6":true},
 {"n":"น.ท.ปรัฒสดางค์",   "d5":"",          "d6":"2026-09-11","q5":true,"q6":true},
 {"n":"น.ต.ธนบัตร",       "d5":"2026-07-23","d6":"2026-09-05","q5":true,"q6":true},
 {"n":"น.ต.ณภัทร",        "d5":"2025-08-04","d6":"2026-08-26","q5":true,"q6":true},
 {"n":"ร.อ.พงศ์วิสิฐ",    "d5":"2025-04-23","d6":"2026-06-25","q5":true,"q6":true},
 {"n":"ร.อ.บดีพล",        "d5":"2026-09-01","d6":"",          "q5":true,"q6":false},
 {"n":"น.ท.สุทธิรัตน์",   "d5":"2026-08-28","d6":"2026-09-03","q5":true,"q6":true},
 {"n":"น.ต.อนันต์ชัย",    "d5":"2025-10-24","d6":"2025-12-30","q5":true,"q6":true},
 {"n":"น.ต.ธนะภัทร์",     "d5":"2026-09-11","d6":"2026-09-01","q5":true,"q6":true},
 {"n":"น.ต.วันทชัย",      "d5":"2026-08-24","d6":"2026-09-07","q5":true,"q6":true},
 {"n":"น.ต.ธนากร",        "d5":"2026-07-16","d6":"2026-09-08","q5":true,"q6":true},
 {"n":"น.ต.ณัฐดนัย",      "d5":"2026-09-01","d6":"2026-08-10","q5":true,"q6":true},
 {"n":"น.ต.ธนัช",         "d5":"2026-09-03","d6":"2026-09-08","q5":true,"q6":true},
 {"n":"น.ต.ศรราม",        "d5":"2026-09-08","d6":"2026-09-05","q5":true,"q6":true},
 {"n":"น.ต.ธนกร",         "d5":"2026-09-10","d6":"2026-09-09","q5":true,"q6":true},
 {"n":"ร.อ.นฤดล",         "d5":"2026-08-19","d6":"2026-09-11","q5":true,"q6":true},
 {"n":"ร.อ.ไกรรัฐ",       "d5":"2026-08-25","d6":"2026-09-09","q5":true,"q6":true},
 {"n":"ร.อ.ฐาธิปัตย์",    "d5":"2026-08-24","d6":"2026-09-10","q5":true,"q6":true},
 {"n":"ร.อ.วรพงษ์",       "d5":"2026-09-10","d6":"2026-09-03","q5":true,"q6":true},
 {"n":"ร.อ.ภานุวัฒน์",    "d5":"2026-07-19","d6":"2026-08-16","q5":true,"q6":true},
 {"n":"ร.อ.กิตติคม",      "d5":"2026-08-26","d6":"2026-09-08","q5":true,"q6":true},
 {"n":"ร.อ.ยุทธพล",       "d5":"2026-09-10","d6":"2026-09-07","q5":true,"q6":true},
 {"n":"ร.อ.วีระพล",       "d5":"2026-09-11","d6":"2026-08-31","q5":true,"q6":true},
 {"n":"ร.อ.ณัฐกิจ",       "d5":"2026-09-08","d6":"2026-09-10","q5":true,"q6":true},
 {"n":"ร.อ.สตภัทร",       "d5":"2026-09-09","d6":"2026-09-05","q5":true,"q6":true},
 {"n":"ร.อ.บัณฑิต",       "d5":"2026-09-10","d6":"",          "q5":true,"q6":false},
 {"n":"ร.อ.ภวิล",         "d5":"2026-08-24","d6":"2026-09-04","q5":true,"q6":true},
 {"n":"ร.ท.เจษฎา",        "d5":"",          "d6":"2026-09-10","q5":false,"q6":true},
 {"n":"ร.ท.ศุภวิชญ์",     "d5":"",          "d6":"2026-09-09","q5":false,"q6":true},
 {"n":"ร.ท.ณภัทร",        "d5":"",          "d6":"2026-09-10","q5":false,"q6":true},
 {"n":"ร.ท.พฤกษ์",        "d5":"",          "d6":"2026-09-03","q5":false,"q6":true},
 {"n":"ร.ท.มหินทรา",      "d5":"",          "d6":"2026-09-10","q5":false,"q6":true},
 {"n":"ร.ท.ตรัย",         "d5":"",          "d6":"2026-09-11","q5":false,"q6":true},
 {"n":"ร.ท.ฤทธิเดช",      "d5":"",          "d6":"2026-09-07","q5":false,"q6":true},
 {"n":"ร.ท.วสุพล",        "d5":"",          "d6":"2026-09-03","q5":false,"q6":true},
 {"n":"ร.ท.ชยพล",         "d5":"",          "d6":"2026-09-03","q5":false,"q6":true}
]$json$::jsonb) as t(x);

-- ===== ดันวันบินล่าสุดให้ทันสมัยจากรายงานหลังบินจริง (รวมเที่ยวบิน 3 วันล่าสุด) =====
-- นับเฉพาะที่เป็นนักบิน (AC/IP/P/CP/N) และภารกิจมีรายงานหลังบินแล้ว · ดันไปข้างหน้าเท่านั้น
with flown as (
  select mc.crew_member_id as cid,
         case when a.type ilike '%500%' then 5 when a.type ilike '%600%' then 6 end as tp,
         max(m.mission_date) as d
    from public.mission_crew mc
    join public.missions m on m.id = mc.mission_id
    join public.aircraft a on a.id = m.aircraft_id
    join public.post_flight_reports r on r.mission_id = m.id
   where mc.crew_member_id is not null
     and upper(coalesce(mc.position,'')) in ('AC','IP','P','CP','N')
     and coalesce(m.status,'') <> 'cancelled'
   group by mc.crew_member_id, 2
)
update public.crew_members c set
  last_500_date = greatest(c.last_500_date, (select d from flown where cid=c.id and tp=5)),
  last_600_date = greatest(c.last_600_date, (select d from flown where cid=c.id and tp=6));

select count(*) filter (where can_fly_500) as "บิน500ได้",
       count(*) filter (where can_fly_600) as "บิน600ได้",
       count(*) as "นักบินทั้งหมด" from public.crew_members;
