-- =====================================================================
--  Flight Operation · migration_02_aircraft_and_cleanup.sql
--   1) ใส่รายการเครื่องบินประจำการ 6 ลำ (ตายตัว — ไม่ต้องเพิ่มเองในเว็บ)
--   2) ลบคอลัมน์ ระยะทาง / เวลา / ความสูง ที่ไม่ใช้
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

-- ---------- 1) เครื่องบินประจำการ ----------
insert into public.aircraft (tail_number, type) values
  ('60301', 'ATR72-600'),
  ('60302', 'ATR72-600'),
  ('60303', 'ATR72-600'),
  ('60313', 'ATR72-500'),
  ('60315', 'ATR72-500'),
  ('60316', 'ATR72-500')
on conflict (tail_number) do nothing;

-- ---------- 2) ลบฟิลด์ที่ไม่ใช้ ----------
alter table public.missions
  drop column if exists distance,
  drop column if exists duration,
  drop column if exists altitude;

-- =====================================================================
--  ตรวจผล: select type || '/' || tail_number as ac from aircraft order by tail_number;
--  ควรได้ ATR72-600/60301, 60302, 60303, ATR72-500/60313, 60315, 60316
-- =====================================================================
