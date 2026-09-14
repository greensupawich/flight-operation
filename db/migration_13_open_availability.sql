-- =====================================================================
--  Flight Operation · migration_13_open_availability.sql
--  หน้าวัน: ผู้ใช้ที่ได้รับอนุมัติทุกคน เพิ่ม/ลบ "นักบินที่ไม่ว่าง" ของนักบินคนไหนก็ได้
--  (เดิมแก้ได้เฉพาะของตัวเอง) · เก็บว่าใครเป็นคนเพิ่มไว้ใน created_by
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================
alter table public.crew_unavailable
  add column if not exists created_by uuid references public.profiles(id) on delete set null
  default auth.uid();

drop policy if exists p_unavail_self_ins on public.crew_unavailable;
drop policy if exists p_unavail_self_upd on public.crew_unavailable;
drop policy if exists p_unavail_self_del on public.crew_unavailable;

drop policy if exists p_unavail_active_write on public.crew_unavailable;
create policy p_unavail_active_write on public.crew_unavailable for all
  using ( public.is_active() ) with check ( public.is_active() );
