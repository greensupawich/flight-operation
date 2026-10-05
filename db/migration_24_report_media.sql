-- =====================================================================
--  Flight Operation · migration_24_report_media.sql
--  แนบรูป / วีดีโอ ในข้อขัดข้อง และรายงานอันตราย (Safety Report)
--   • ไฟล์จริงเก็บใน Supabase Storage bucket 'report-media' (private)
--       path = <mission_id>/<uuid>.<ext>   — จำกัด 50 MB/ไฟล์ · เฉพาะ image/* และ video/*
--       (รูปถูกย่อในเบราว์เซอร์ก่อนอัปโหลด เหลือ ~200–400 KB)
--   • ตาราง report_media = รายการไฟล์ ผูกกับ "ข้อขัดข้อง" หรือ "รายงานอันตราย" อย่างใดอย่างหนึ่ง
--   • สิทธิ์: ดู = active · แนบ = planner หรือคนที่บินภารกิจนั้น · ลบ = planner หรือคนที่อัปโหลดเอง
--  ต้องรัน migration_23 (safety_reports) มาก่อน · รันซ้ำได้ ปลอดภัย
-- =====================================================================

-- ---------- 1) bucket ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-media', 'report-media', false, 52428800, array['image/*', 'video/*'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------- 2) ตารางรายการไฟล์ ----------
create table if not exists public.report_media (
  id                uuid primary key default gen_random_uuid(),
  mission_id        uuid not null references public.missions(id) on delete cascade,
  discrepancy_id    uuid references public.discrepancies(id) on delete cascade,
  safety_report_id  uuid references public.safety_reports(id) on delete cascade,
  storage_path      text not null unique,
  mime_type         text,
  file_name         text,
  size_bytes        bigint,
  created_by        uuid default auth.uid(),
  created_at        timestamptz not null default now(),
  constraint report_media_one_parent check (num_nonnulls(discrepancy_id, safety_report_id) = 1)
);
create index if not exists idx_media_mission on public.report_media(mission_id);
create index if not exists idx_media_disc    on public.report_media(discrepancy_id);
create index if not exists idx_media_safety  on public.report_media(safety_report_id);

alter table public.report_media enable row level security;

drop policy if exists p_media_read on public.report_media;
create policy p_media_read on public.report_media for select using ( public.is_active() );

drop policy if exists p_media_insert on public.report_media;
create policy p_media_insert on public.report_media for insert
  with check ( public.is_active() and (public.can_plan() or public.flies_mission(mission_id)) );

drop policy if exists p_media_delete on public.report_media;
create policy p_media_delete on public.report_media for delete
  using ( public.can_plan() or created_by = auth.uid() );

-- ---------- 3) สิทธิ์ใน Storage ----------
-- โฟลเดอร์แรกของ path = mission_id · ตรวจรูปแบบ uuid ก่อน cast กัน error
create or replace function public.media_folder_ok(folder text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    public.can_plan()
    or (folder ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and public.flies_mission(folder::uuid)));
$$;

drop policy if exists rm_read on storage.objects;
create policy rm_read on storage.objects for select to authenticated
  using ( bucket_id = 'report-media' and public.is_active() );

drop policy if exists rm_insert on storage.objects;
create policy rm_insert on storage.objects for insert to authenticated
  with check ( bucket_id = 'report-media' and public.media_folder_ok((storage.foldername(name))[1]) );

drop policy if exists rm_delete on storage.objects;
create policy rm_delete on storage.objects for delete to authenticated
  using ( bucket_id = 'report-media' and (public.can_plan() or owner_id = auth.uid()::text) );

