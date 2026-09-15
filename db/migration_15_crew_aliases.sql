-- =====================================================================
--  Flight Operation · migration_15_crew_aliases.sql
--  "ชื่อเดิม / ชื่ออื่น" ของนักบิน — ชื่อหลายแบบชี้ไปที่รหัสเดียวกัน
--  ใช้ตอนยศเปลี่ยน เช่น ร.ท.ณภัทร = ร.อ.ณภัทร (มีนักบินชื่อ ณภัทร 2 คน จึงเดาจากชื่ออย่างเดียวไม่ได้)
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

create table if not exists public.crew_aliases (
  alias           text primary key,          -- เก็บแบบตัดช่องว่างออกทั้งหมด
  crew_member_id  uuid not null references public.crew_members(id) on delete cascade,
  created_at      timestamptz not null default now()
);
create index if not exists idx_crew_aliases_member on public.crew_aliases(crew_member_id);

create or replace function public.normalize_crew_alias()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.alias := regexp_replace(coalesce(new.alias, ''), '\s', '', 'g');
  if new.alias = '' then raise exception 'ชื่อเดิมห้ามว่าง'; end if;
  if exists (select 1 from public.crew_members
              where regexp_replace(full_name, '\s', '', 'g') = new.alias and id <> new.crew_member_id) then
    raise exception '"%" เป็นชื่อปัจจุบันของนักบินคนอื่นในทะเบียน', new.alias;
  end if;
  return new;
end $$;

drop trigger if exists trg_normalize_crew_alias on public.crew_aliases;
create trigger trg_normalize_crew_alias before insert or update on public.crew_aliases
  for each row execute function public.normalize_crew_alias();

alter table public.crew_aliases enable row level security;
drop policy if exists p_alias_read on public.crew_aliases;
create policy p_alias_read on public.crew_aliases for select using ( public.is_active() );
drop policy if exists p_alias_write on public.crew_aliases;
create policy p_alias_write on public.crew_aliases for all
  using ( public.can_plan() ) with check ( public.can_plan() );

-- ---------- ชื่อเดิมที่พบในข้อมูล ก.ย. ----------
insert into public.crew_aliases (alias, crew_member_id)
select v.alias, c.id
  from (values ('ร.ท.ณภัทร', 'ร.อ.ณภัทร'),
               ('ร.ท.ศุภวิชญ์', 'ร.อ.ศุภวิชญ์'),
               ('ร.ท.พฤกษ์', 'ร.อ.พฤกษ์')) as v(alias, current_name)
  join public.crew_members c on regexp_replace(c.full_name, '\s', '', 'g') = v.current_name
on conflict (alias) do update set crew_member_id = excluded.crew_member_id;

-- ---------- ผูกลูกเรือในภารกิจที่ยังไม่ได้ผูก ด้วยชื่อเดิม ----------
update public.mission_crew mc
   set crew_member_id = a.crew_member_id
  from public.crew_aliases a
 where mc.crew_member_id is null
   and upper(btrim(mc.position)) in ('AC', 'IP', 'P', 'CP', 'N')
   and regexp_replace(regexp_replace(mc.crew_name, '\([^)]*\)', '', 'g'), '\s', '', 'g') = a.alias;

-- ---------- ตรวจผล ----------
select a.alias as "ชื่อเดิม", c.full_name as "ชื่อปัจจุบัน", c.code as "รหัส"
  from public.crew_aliases a join public.crew_members c on c.id = a.crew_member_id
 order by c.code;
