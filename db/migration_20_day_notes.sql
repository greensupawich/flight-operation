-- =====================================================================
--  Flight Operation · migration_20_day_notes.sql
--  บันทึกระดับ "วัน" สำหรับกระดานจัดบิน — เริ่มจาก น.จัดบินภารกิจ (วันถัดไป)
--   • 1 แถวต่อ 1 วัน (log_date = วันของกระดาน)
--   • แก้ได้เฉพาะ admin/planner (can_plan) · อ่านได้ทุกคนที่ active (is_active)
--   • รันซ้ำได้ ปลอดภัย
-- =====================================================================
create table if not exists public.day_notes (
  log_date      date primary key,
  duty_officer  text,               -- ชื่อ น.จัดบินภารกิจ (วันถัดไป)
  duty_phone    text,               -- เบอร์ติดต่อ
  updated_by    uuid,
  updated_at    timestamptz not null default now()
);

alter table public.day_notes enable row level security;

drop policy if exists p_daynotes_read on public.day_notes;
create policy p_daynotes_read on public.day_notes for select using ( public.is_active() );

drop policy if exists p_daynotes_write on public.day_notes;
create policy p_daynotes_write on public.day_notes for all
  using ( public.can_plan() ) with check ( public.can_plan() );
