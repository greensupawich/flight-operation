-- =====================================================================
--  Flight Operation · migration_12_queue_entries.sql
--  ช่องในหน้าคิวบินที่ผู้วางแผน/admin พิมพ์แก้เองได้ (แบบ Excel)
--   • 1 ช่อง (นักบิน × วัน) = 1 รายการ
--   • code    : ข้อความในช่อง เช่น CNX / ST / LB (ว่างได้ = สีอย่างเดียว)
--   • kind    : สีชนิดภารกิจ
--   • ac_type : '600' ตัวดำ / '500' ตัวแดง
--   ถ้าช่องมีรายการนี้ จะแสดงแทนข้อมูลที่คำนวณจากภารกิจในช่องนั้น
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================
create table if not exists public.queue_entries (
  id              uuid primary key default gen_random_uuid(),
  crew_member_id  uuid not null references public.crew_members(id) on delete cascade,
  entry_date      date not null,
  code            text,
  kind            text not null default 'rtaf'
                  check (kind in ('fcf','dechochai','palace','rtaf','training','stby')),
  ac_type         text check (ac_type in ('600','500')),
  updated_by      uuid references public.profiles(id) on delete set null,
  updated_at      timestamptz not null default now(),
  unique (crew_member_id, entry_date)
);
create index if not exists idx_queue_entries_date on public.queue_entries(entry_date);

alter table public.queue_entries enable row level security;
drop policy if exists p_qe_read on public.queue_entries;
create policy p_qe_read on public.queue_entries for select using ( public.is_active() );
drop policy if exists p_qe_write on public.queue_entries;
create policy p_qe_write on public.queue_entries for all
  using ( public.can_plan() ) with check ( public.can_plan() );
