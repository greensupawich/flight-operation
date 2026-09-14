-- =====================================================================
--  Flight Operation · migration_07_mission_kinds.sql
--  ชนิดภารกิจตามกระดานจัดบินจริง (5 ชนิด):
--    fcf        = F.C.F
--    dechochai  = เดโชชัย
--    palace     = ภารกิจสำนักพระราชวัง
--    rtaf       = ภารกิจ ทอ.
--    training   = ฝึกบิน
--  เปลี่ยนคอลัมน์จาก enum → text + check (เพิ่ม/ลดชนิดภายหลังได้ง่ายกว่า enum)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

alter table public.missions alter column kind drop default;
alter table public.missions alter column kind type text using kind::text;

-- ชนิดเดิมที่ไม่มีในชุดใหม่ (กห. / อื่นๆ) → ภารกิจ ทอ.  (แก้รายภารกิจได้ในหน้าเว็บ)
update public.missions
   set kind = 'rtaf'
 where kind is null
    or kind not in ('fcf', 'dechochai', 'palace', 'rtaf', 'training');

alter table public.missions alter column kind set default 'rtaf';
alter table public.missions alter column kind set not null;

alter table public.missions drop constraint if exists missions_kind_check;
alter table public.missions add constraint missions_kind_check
  check (kind in ('fcf', 'dechochai', 'palace', 'rtaf', 'training'));

drop type if exists mission_kind;
