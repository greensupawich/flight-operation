-- =====================================================================
--  Flight Operation · migration_11_self_availability.sql
--  นักบินติ๊ก "ไม่ว่าง" + หมายเหตุ ของตัวเองได้จากหน้าวัน
--   • crew_members.profile_id = ผูกบัญชีที่ล็อกอินกับชื่อในทะเบียนนักบิน (1 บัญชี : 1 ชื่อ)
--   • นักบินเลือกชื่อตัวเองได้ครั้งเดียว (เฉพาะชื่อที่ยังไม่มีใครผูก) · admin/ผู้วางแผนแก้ได้
--   • เขียน crew_unavailable ได้เฉพาะแถวของตัวเอง (ผู้วางแผนยังแก้ได้ทุกคนเหมือนเดิม)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

alter table public.crew_members
  add column if not exists profile_id uuid references public.profiles(id) on delete set null;
create unique index if not exists crew_members_profile_key
  on public.crew_members(profile_id) where profile_id is not null;

-- id ในทะเบียนของผู้ใช้ที่ล็อกอินอยู่
create or replace function public.my_crew_member_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.crew_members where profile_id = auth.uid() limit 1;
$$;

-- ---------- ผูกชื่อตัวเอง (ผ่านฟังก์ชัน เพื่อไม่ให้แก้ข้อมูลอื่นในทะเบียนได้) ----------
create or replace function public.claim_crew_member(p_crew uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then
    raise exception 'บัญชียังไม่ได้รับอนุมัติ';
  end if;
  if exists (select 1 from public.crew_members where profile_id = auth.uid()) then
    raise exception 'บัญชีของคุณผูกกับรายชื่อในทะเบียนแล้ว — ถ้าผูกผิด ให้ admin แก้ในหน้าทะเบียนนักบิน';
  end if;
  update public.crew_members set profile_id = auth.uid()
   where id = p_crew and profile_id is null and active;
  if not found then
    raise exception 'รายชื่อนี้ถูกผูกกับบัญชีอื่นแล้ว หรือไม่มีในทะเบียน';
  end if;
end $$;
grant execute on function public.claim_crew_member(uuid) to authenticated;

-- ---------- สิทธิ์ crew_unavailable: เจ้าของแถวแก้ของตัวเองได้ ----------
drop policy if exists p_unavail_self_ins on public.crew_unavailable;
create policy p_unavail_self_ins on public.crew_unavailable for insert
  with check ( public.is_active() and crew_member_id = public.my_crew_member_id() );

drop policy if exists p_unavail_self_upd on public.crew_unavailable;
create policy p_unavail_self_upd on public.crew_unavailable for update
  using ( public.is_active() and crew_member_id = public.my_crew_member_id() )
  with check ( public.is_active() and crew_member_id = public.my_crew_member_id() );

drop policy if exists p_unavail_self_del on public.crew_unavailable;
create policy p_unavail_self_del on public.crew_unavailable for delete
  using ( public.is_active() and crew_member_id = public.my_crew_member_id() );
