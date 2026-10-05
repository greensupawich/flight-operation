-- =====================================================================
--  Flight Operation · migration_27_stby_dechochai.sql
--  เพิ่มชนิดภารกิจ "STBY เดโชชัย" (stby_dechochai)
--   • เงื่อนไขเหมือน STBY: เตรียมพร้อม ยังไม่ปฏิบัติจริง — ขึ้นในบล็อก STBY ของกระดาน,
--     ในคิวบินเป็นช่อง ST (ไม่นับเป็นเที่ยวบินจริง), ไม่อยู่ในตารางสถิติแยกประเภท
--   • ถ้าถูกเรียกใช้ ผู้เกี่ยวข้องแก้ภารกิจเปลี่ยนชนิดเป็น "เดโชชัย" เอง
--  รันซ้ำได้ ปลอดภัย
-- =====================================================================
alter table public.missions drop constraint if exists missions_kind_check;
alter table public.missions add constraint missions_kind_check
  check (kind in ('fcf', 'dechochai', 'palace', 'rtaf', 'training', 'stby', 'stby_dechochai'));

-- ช่องคิวบินที่พิมพ์เอง (queue_entries) เลือกสีชนิดนี้ได้ด้วย
alter table public.queue_entries drop constraint if exists queue_entries_kind_check;
alter table public.queue_entries add constraint queue_entries_kind_check
  check (kind in ('fcf', 'dechochai', 'palace', 'rtaf', 'training', 'stby', 'stby_dechochai'));
