-- =====================================================================
--  Flight Operation · migration_10_admin_limit.sql
--  • admin ได้สูงสุด 3 คน (รวมผู้ดูแลหลัก)
--  • ผู้ดูแลหลัก green.supawich@gmail.com: ถอดสิทธิ์ ปิดการใช้งาน หรือลบ ไม่ได้
--  บังคับที่ฐานข้อมูล (trigger) — เลี่ยงผ่านหน้าเว็บหรือ API ไม่ได้
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

create or replace function public.default_admin_email()
returns text language sql immutable as $$ select 'green.supawich@gmail.com'::text $$;

create or replace function public.admin_count(exclude_id uuid default null)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.profiles
   where role = 'admin' and (exclude_id is null or id <> exclude_id);
$$;

-- ---------- กฎ admin บนตาราง profiles ----------
create or replace function public.guard_admin_rules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if lower(old.email) = public.default_admin_email() then
      raise exception 'ไม่สามารถลบผู้ดูแลหลัก (%) ได้', old.email;
    end if;
    return old;
  end if;

  -- ผู้ดูแลหลัก: เป็น admin และใช้งานอยู่เสมอ
  if lower(new.email) = public.default_admin_email() then
    if tg_op = 'UPDATE' and (new.role <> 'admin' or new.status <> 'active') then
      raise exception 'ไม่สามารถถอดสิทธิ์หรือปิดการใช้งานผู้ดูแลหลัก (%) ได้', new.email;
    end if;
    new.role := 'admin';
    new.status := 'active';
    return new;
  end if;

  -- จำกัด admin ไม่เกิน 3 คน
  if new.role = 'admin' and (tg_op = 'INSERT' or old.role is distinct from 'admin') then
    if public.admin_count(new.id) >= 3 then
      raise exception 'มีผู้ดูแลระบบครบ 3 คนแล้ว — ต้องถอดสิทธิ์ admin ของคนอื่นก่อน';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_admin_rules on public.profiles;
create trigger trg_guard_admin_rules
  before insert or update or delete on public.profiles
  for each row execute function public.guard_admin_rules();

-- ---------- เพิ่มผู้ใช้ล่วงหน้า: อนุญาต role admin แต่นับรวมโควตา 3 คน ----------
create or replace function public.normalize_invite()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.email := lower(btrim(new.email));
  if new.email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'อีเมลไม่ถูกต้อง: %', new.email;
  end if;

  if new.role = 'admin' and new.email <> public.default_admin_email() then
    if (select count(*) from public.profiles
         where role = 'admin' and lower(email) <> new.email)
     + (select count(*) from public.user_invites i
         where i.role = 'admin' and i.email <> new.email
           and not exists (select 1 from public.profiles p where lower(p.email) = i.email)) >= 3 then
      raise exception 'มีผู้ดูแลระบบ (รวมที่เพิ่มล่วงหน้าไว้) ครบ 3 คนแล้ว';
    end if;
  end if;
  return new;
end $$;

-- ---------- ล็อกอินครั้งแรก: ถ้าเชิญเป็น admin แต่โควตาเต็มแล้ว → รออนุมัติแทน (ไม่ให้สมัครพัง) ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_first  boolean;
  v_admin  boolean;
  v_role   user_role;
  v_status user_status;
  inv      public.user_invites%rowtype;
begin
  select count(*) = 0 into v_first from public.profiles;
  v_admin := v_first or lower(new.email) = public.default_admin_email();

  select * into inv from public.user_invites where email = lower(btrim(new.email));

  if v_admin then
    v_role := 'admin';  v_status := 'active';
  elsif inv.email is not null then
    v_role := inv.role; v_status := 'active';
    if v_role = 'admin' and public.admin_count(null) >= 3 then
      v_role := 'viewer'; v_status := 'pending';
    end if;
  else
    v_role := 'viewer'; v_status := 'pending';
  end if;

  insert into public.profiles (id, email, full_name, rank, role, status)
  values (
    new.id, new.email,
    coalesce(nullif(btrim(inv.full_name), ''),
             new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    nullif(btrim(inv.rank), ''),
    v_role, v_status
  )
  on conflict (id) do nothing;

  if inv.email is not null and v_status = 'active' then
    update public.user_invites set used_at = now() where email = inv.email;
  end if;
  return new;
end $$;

-- ---------- ตรวจผล ----------
select email, role, status from public.profiles where role = 'admin' order by email;
