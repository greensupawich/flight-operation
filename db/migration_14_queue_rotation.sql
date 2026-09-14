-- =====================================================================
--  Flight Operation · migration_14_queue_rotation.sql
--  ช่องติ๊ก "นับคิว" หน้าชื่อนักบินในหน้าคิวบิน (ติ๊กไว้ทุกคนเป็นค่าเริ่มต้น)
--  แก้ได้เฉพาะผู้วางแผน/admin (ใช้สิทธิ์เขียน crew_members เดิม)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย) — ต้องรัน catchup_2026_09_14.sql ก่อน
-- =====================================================================
alter table public.crew_members
  add column if not exists in_queue boolean not null default true;
