-- =====================================================================
--  Flight Operation · migration_23_safety_reports.sql
--  รายงานอันตราย (Safety Report) ต่อภารกิจ — ไม่บังคับ · มีได้หลายรายการ/ภารกิจ
--   • วันที่ / นักบิน / เส้นทางบิน ดึงจากภารกิจ (mission) ตอนแสดง ไม่ต้องเก็บซ้ำ
--   • เก็บเฉพาะช่องที่กรอกเพิ่ม: occurred_time (เวลา) + description (ลักษณะเหตุการณ์)
--   • สิทธิ์เหมือนรายงานหลังบิน: อ่าน = active · เขียน = planner หรือคนที่บินภารกิจนั้น
--  ต้องรัน policies.sql (helper is_active/can_plan/flies_mission) มาก่อน · รันซ้ำได้
-- =====================================================================
create table if not exists public.safety_reports (
  id            uuid primary key default gen_random_uuid(),
  mission_id    uuid not null references public.missions(id) on delete cascade,
  occurred_time text,                 -- เวลาที่เกิดเหตุ (ข้อความ เช่น '1015')
  description   text not null,        -- ลักษณะเหตุการณ์
  created_by    uuid,
  created_at    timestamptz not null default now()
);
create index if not exists idx_safety_mission on public.safety_reports(mission_id, created_at);

alter table public.safety_reports enable row level security;

drop policy if exists p_safety_read on public.safety_reports;
create policy p_safety_read on public.safety_reports for select using ( public.is_active() );

drop policy if exists p_safety_write on public.safety_reports;
create policy p_safety_write on public.safety_reports for all
  using ( public.can_plan() or public.flies_mission(mission_id) )
  with check ( public.can_plan() or public.flies_mission(mission_id) );
