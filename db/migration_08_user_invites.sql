-- =====================================================================
--  Flight Operation · migration_08_user_invites.sql
--  admin เพิ่มอีเมลผู้ใช้ล่วงหน้า (manual) ได้
--
--  บัญชีใน Supabase ถูกสร้างตอนล็อกอิน Google ครั้งแรกเท่านั้น จึงเก็บเป็น
--  "รายชื่ออีเมลที่อนุญาตล่วงหน้า" (user_invites):
--   • ยังไม่เคยล็อกอิน → พอล็อกอินครั้งแรก เปิดใช้งานทันทีตามสิทธิ์ที่ตั้งไว้ (ไม่ต้องขอใช้งาน)
--   • ล็อกอินแล้วแต่ยังรออนุมัติ → เปิดใช้งานทันทีที่ admin เพิ่มอีเมล
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

create table if not exists public.user_invites (
  email       text primary key,                     -- เก็บเป็นตัวพิมพ์เล็กเสมอ
  full_name   text,
  rank        text,                                 -- ตำแหน่ง
  role        user_role not null default 'crew',
  invited_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  used_at     timestamptz                           -- เวลาที่เจ้าของอีเมลได้รับสิทธิ์จริง
);

-- ---------- ปรับอีเมลให้เป็นมาตรฐาน (ตัดช่องว่าง + ตัวพิมพ์เล็ก) ----------
create or replace function public.normalize_invite()
returns trigger language plpgsql as $$
begin
  new.email := lower(btrim(new.email));
  if new.email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'อีเมลไม่ถูกต้อง: %', new.email;
  end if;
  if new.role = 'admin' then
    raise exception 'เพิ่มผู้ใช้เป็น admin ไม่ได้ (admin มีได้คนเดียว)';
  end if;
  return new;
end $$;

drop trigger if exists trg_normalize_invite on public.user_invites;
create trigger trg_normalize_invite before insert or update on public.user_invites
  for each row execute function public.normalize_invite();

-- ---------- สิทธิ์: เฉพาะ admin ----------
alter table public.user_invites enable row level security;
drop policy if exists p_invites_admin on public.user_invites;
create policy p_invites_admin on public.user_invites for all
  using ( public.is_admin() ) with check ( public.is_admin() );

-- =====================================================================
--  ผู้ใช้ล็อกอินครั้งแรก → ถ้ามีอีเมลในรายชื่อที่อนุญาต เปิดใช้งานทันที
-- =====================================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_first boolean;
  v_admin boolean;
  inv     public.user_invites%rowtype;
begin
  select count(*) = 0 into v_first from public.profiles;
  v_admin := v_first or lower(new.email) = 'green.supawich@gmail.com';

  select * into inv from public.user_invites where email = lower(btrim(new.email));

  insert into public.profiles (id, email, full_name, rank, role, status)
  values (
    new.id,
    new.email,
    coalesce(nullif(btrim(inv.full_name), ''),
             new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    nullif(btrim(inv.rank), ''),
    case when v_admin then 'admin'::user_role
         when inv.email is not null then inv.role
         else 'viewer'::user_role end,
    case when v_admin or inv.email is not null then 'active'::user_status
         else 'pending'::user_status end
  )
  on conflict (id) do nothing;

  if inv.email is not null then
    update public.user_invites set used_at = now() where email = inv.email;
  end if;

  return new;
end $$;

-- =====================================================================
--  admin เพิ่ม/แก้อีเมล ของคนที่ล็อกอินไว้แล้ว (เช่นรออนุมัติอยู่) → เปิดใช้งานทันที
--  (ไม่ผูกกับคอลัมน์ used_at เพื่อกัน trigger ทำงานวนซ้ำ)
-- =====================================================================
create or replace function public.apply_invite_to_existing()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles p
     set status    = 'active',
         role      = new.role,
         full_name = coalesce(nullif(btrim(new.full_name), ''), p.full_name),
         rank      = coalesce(nullif(btrim(new.rank), ''), p.rank)
   where lower(p.email) = new.email
     and p.role <> 'admin';                          -- ไม่แตะบัญชี admin

  if found then
    update public.user_invites set used_at = now()
     where email = new.email and used_at is null;
  end if;
  return new;
end $$;

drop trigger if exists trg_apply_invite on public.user_invites;
create trigger trg_apply_invite
  after insert or update of role, full_name, rank on public.user_invites
  for each row execute function public.apply_invite_to_existing();
