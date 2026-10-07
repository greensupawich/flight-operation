-- =====================================================================
--  Flight Operation · migration_29_display_order.sql
--  ลำดับการ์ดภารกิจที่ผู้วางแผนจัดเอง (ลากวาง) ในหน้าหลัก / หน้าภารกิจรายวัน
--   • missions.display_order : ลำดับภายในวัน (null = ยังไม่จัด → เรียงตาม T/O)
--   • แก้ได้ตามสิทธิ์ missions เดิม (can_plan)
--  รันซ้ำได้ ปลอดภัย
-- =====================================================================
alter table public.missions add column if not exists display_order int;
create index if not exists idx_missions_date_order on public.missions(mission_date, display_order);
