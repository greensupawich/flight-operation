-- =====================================================================
--  Flight Operation · seed_pilots.sql
--  นำเข้ารายชื่อนักบิน 42 ท่าน + คุณวุฒิ (IP / P / CP) เข้าทะเบียนนักบิน
--
--  • รหัสตั้งให้ตามลำดับรายชื่อ: P001 ... P042
--  • ชื่อที่มีในทะเบียนอยู่แล้ว (เทียบแบบไม่สนช่องว่าง) → ไม่สร้างซ้ำ แต่อัปเดตคุณวุฒิให้
--  • ถ้ารหัสตามลำดับถูกคนอื่นใช้ไปแล้ว → ใช้รหัสว่างถัดไปแทน
--  • คุณวุฒิเก็บในช่อง position ของทะเบียน
--
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ไม่สร้างซ้ำ)
-- =====================================================================
do $$
declare
  pilots text[][] := array[
    ['น.อ.ฉัตฤกษ์','IP'],   ['น.อ.ชญานิน','IP'],   ['น.อ.บุญธรัฐ','IP'],    ['น.อ.จิราพงษ์','IP'],
    ['น.อ.เอกราช','IP'],    ['น.ท.วรุตม์','IP'],    ['น.ท.สกุลกอ','IP'],     ['น.ท.ปรัฒสดางค์','IP'],
    ['น.ต.ธนบัตร','IP'],    ['น.ต.ณภัทร','P'],      ['น.ต.พงศ์วิสิฐ','CP'],  ['ร.อ.บดีพล','CP'],
    ['น.ท.สุทธิรัตน์','IP'], ['น.ต.อนันต์ชัย','IP'], ['น.ต.ธนะภัทร์','IP'],   ['น.ต.วันทชัย','IP'],
    ['น.ต.ธนากร','P'],      ['น.ต.ณัฐดนัย','IP'],   ['น.ต.ธนัช','IP'],       ['น.ต.ศรราม','IP'],
    ['น.ต.ธนกร','P'],       ['ร.อ.นฤดล','P'],       ['ร.อ.ไกรรัฐ','CP'],     ['ร.อ.ฐาธิปัตย์','CP'],
    ['ร.อ.วรพงษ์','CP'],    ['ร.อ.ภานุวัฒน์','CP'], ['ร.อ.กิตติคม','CP'],    ['ร.อ.ยุทธพล','CP'],
    ['ร.อ.วีระพล','CP'],    ['ร.อ.ณัฐกิจ','CP'],    ['ร.อ.สตภัทร','CP'],     ['ร.อ.บัณฑิต','CP'],
    ['ร.อ.ภวิล','CP'],      ['ร.อ.เจษฎา','CP'],     ['ร.อ.ศุภวิชญ์','CP'],   ['ร.อ.ณภัทร','CP'],
    ['ร.อ.พฤกษ์','CP'],     ['ร.อ.มหินทรา','CP'],   ['ร.ท.ตรัย','CP'],       ['ร.ท.ฤทธิเดช','CP'],
    ['ร.ท.วสุพล','CP'],     ['ร.ท.ชยพล','CP']
  ];
  n        int := array_length(pilots, 1);
  i        int;
  nm       text;
  q        text;
  v_code   text;
  spare    int := array_length(pilots, 1);
  added    int := 0;
  updated  int := 0;
begin
  for i in 1 .. n loop
    nm := btrim(pilots[i][1]);
    q  := pilots[i][2];

    if exists (select 1 from public.crew_members
                where regexp_replace(full_name, '\s', '', 'g') = regexp_replace(nm, '\s', '', 'g')) then
      update public.crew_members
         set position = q
       where regexp_replace(full_name, '\s', '', 'g') = regexp_replace(nm, '\s', '', 'g');
      updated := updated + 1;
      continue;
    end if;

    v_code := 'P' || lpad(i::text, 3, '0');
    while exists (select 1 from public.crew_members where lower(code) = lower(v_code)) loop
      spare  := spare + 1;
      v_code := 'P' || lpad(spare::text, 3, '0');
    end loop;

    insert into public.crew_members (code, full_name, position, active) values (v_code, nm, q, true);
    added := added + 1;
  end loop;

  raise notice 'เพิ่มใหม่ % ท่าน · มีอยู่แล้ว (อัปเดตคุณวุฒิ) % ท่าน', added, updated;
end $$;

-- ---------- ตรวจผล ----------
select position as "คุณวุฒิ", count(*) as "จำนวน"
  from public.crew_members where position in ('IP','P','CP')
 group by position order by position;

select code as "รหัส", full_name as "ชื่อ", position as "คุณวุฒิ"
  from public.crew_members order by code;
