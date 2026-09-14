-- =====================================================================
--  Flight Operation · seed_pilots.sql
--  นำเข้ารายชื่อนักบิน 42 ท่าน เข้าทะเบียนนักบิน (crew_members)
--
--  • รหัสตั้งให้ตามลำดับรายชื่อ: P001, P002, ... P042
--  • ชื่อที่มีในทะเบียนอยู่แล้ว (เทียบแบบไม่สนช่องว่าง) → ข้าม ไม่สร้างซ้ำ
--  • ถ้ารหัสตามลำดับถูกคนอื่นใช้ไปแล้ว → ใช้รหัสว่างถัดไปแทน (P043, P044, ...)
--  • แก้รหัส/ชื่อทีหลังได้ที่หน้า "ทะเบียนนักบิน" — ชม.บินไม่หาย
--
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ไม่สร้างซ้ำ)
-- =====================================================================
do $$
declare
  names text[] := array[
    'น.อ.ฉัตฤกษ์', 'น.อ.ชญานิน', 'น.อ.บุญธรัฐ', 'น.อ.จิราพงษ์', 'น.อ.เอกราช',
    'น.ท.วรุตม์', 'น.ท.สกุลกอ', 'น.ท.ปรัฒสดางค์', 'น.ต.ธนบัตร', 'น.ต.ณภัทร',
    'น.ต.พงศ์วิสิฐ', 'ร.อ.บดีพล', 'น.ท.สุทธิรัตน์', 'น.ต.อนันต์ชัย', 'น.ต.ธนะภัทร์',
    'น.ต.วันทชัย', 'น.ต.ธนากร', 'น.ต.ณัฐดนัย', 'น.ต.ธนัช', 'น.ต.ศรราม',
    'น.ต.ธนกร', 'ร.อ.นฤดล', 'ร.อ.ไกรรัฐ', 'ร.อ.ฐาธิปัตย์', 'ร.อ.วรพงษ์',
    'ร.อ.ภานุวัฒน์', 'ร.อ.กิตติคม', 'ร.อ.ยุทธพล', 'ร.อ.วีระพล', 'ร.อ.ณัฐกิจ',
    'ร.อ.สตภัทร', 'ร.อ.บัณฑิต', 'ร.อ.ภวิล', 'ร.อ.เจษฎา', 'ร.อ.ศุภวิชญ์',
    'ร.อ.ณภัทร', 'ร.อ.พฤกษ์', 'ร.อ.มหินทรา', 'ร.ท.ตรัย', 'ร.ท.ฤทธิเดช',
    'ร.ท.วสุพล', 'ร.ท.ชยพล'
  ];
  i        int;
  nm       text;
  v_code   text;
  spare    int := array_length(names, 1);   -- รหัสสำรองเริ่มต่อจากตัวสุดท้าย
  added    int := 0;
  skipped  int := 0;
begin
  for i in 1 .. array_length(names, 1) loop
    nm := btrim(names[i]);

    -- มีชื่อนี้ในทะเบียนแล้ว → ข้าม
    if exists (select 1 from public.crew_members
                where regexp_replace(full_name, '\s', '', 'g')
                    = regexp_replace(nm, '\s', '', 'g')) then
      skipped := skipped + 1;
      continue;
    end if;

    v_code := 'P' || lpad(i::text, 3, '0');
    while exists (select 1 from public.crew_members where lower(code) = lower(v_code)) loop
      spare  := spare + 1;
      v_code := 'P' || lpad(spare::text, 3, '0');
    end loop;

    insert into public.crew_members (code, full_name, active) values (v_code, nm, true);
    added := added + 1;
  end loop;

  raise notice 'เพิ่มนักบินใหม่ % ท่าน · ข้าม (มีอยู่แล้ว) % ท่าน', added, skipped;
end $$;

-- ---------- ตรวจผล: ทะเบียนทั้งหมดเรียงตามรหัส ----------
select code as "รหัส", full_name as "ชื่อ", position as "ตำแหน่ง", active as "ใช้งาน"
  from public.crew_members
 order by code;
