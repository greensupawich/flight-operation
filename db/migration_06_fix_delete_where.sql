-- =====================================================================
--  Flight Operation · migration_06_fix_delete_where.sql
--
--  แก้บั๊ก: "บันทึกไม่สำเร็จ: DELETE requires a WHERE clause"
--
--  สาเหตุ: Supabase เปิดส่วนขยาย pg-safeupdate สำหรับ role ที่เรียกผ่าน API
--  ซึ่ง "ห้าม DELETE/UPDATE ที่ไม่มี WHERE" เพื่อกันลบข้อมูลยกตารางโดยพลาด
--  ฟังก์ชัน recompute_all_hours() ใช้ `delete from crew_hours;` แบบไม่มี WHERE
--  → รันใน SQL Editor ผ่าน (สิทธิ์ postgres) แต่พอ trigger ทำงานจากหน้าเว็บถูกบล็อก
--  → บันทึกภารกิจไม่ได้
--
--  วิธีแก้: ใส่ WHERE ที่ครอบทุกแถวจริง (id เป็น primary key จึงไม่มีวันเป็น null)
--
--  รันใน Supabase → SQL Editor  (รันซ้ำได้ ปลอดภัย)
-- =====================================================================

create or replace function public.recompute_all_hours()
returns void language plpgsql security definer set search_path = public as $$
begin
  -- ===== ชม.บินรายคน: เฉพาะ IP / P / CP ที่ผูกทะเบียนนักบินไว้ =====
  delete from public.crew_hours where id is not null;   -- WHERE ที่ครอบทุกแถว (กัน pg-safeupdate)

  insert into public.crew_hours (crew_member_id, aircraft_type, total_hours, updated_at)
  select s.crew_member_id, s.ac_type, sum(s.total_hours), now()
  from (
    select distinct m.id as mission_id, mc.crew_member_id,
           coalesce(a.type, '-') as ac_type, r.total_hours
      from public.post_flight_reports r
      join public.missions m      on m.id = r.mission_id
      left join public.aircraft a on a.id = m.aircraft_id
      join public.mission_crew mc on mc.mission_id = m.id
     where mc.crew_member_id is not null
       and coalesce(upper(btrim(mc.position)), '') in ('IP', 'P', 'CP')
  ) s
  group by s.crew_member_id, s.ac_type;

  -- ===== ชม.เครื่อง: รวมจากรายงานทั้งหมดของเครื่องลำนั้น =====
  update public.aircraft a
     set total_hours = coalesce(x.h, 0)
    from (
      select m.aircraft_id, sum(r.total_hours) as h
        from public.post_flight_reports r
        join public.missions m on m.id = r.mission_id
       where m.aircraft_id is not null
       group by m.aircraft_id
    ) x
   where a.id = x.aircraft_id;

  -- เครื่องที่ไม่มีรายงานเลย → 0
  update public.aircraft a
     set total_hours = 0
   where not exists (
     select 1 from public.post_flight_reports r
       join public.missions m on m.id = r.mission_id
      where m.aircraft_id = a.id);
end $$;

-- คำนวณใหม่ 1 ครั้งให้ข้อมูลตรง
select public.recompute_all_hours();

-- =====================================================================
--  ตรวจผล: ควรบันทึกภารกิจจากหน้าเว็บได้แล้ว และ ชม.รายคนขึ้นตามนักบินที่ผูก ✓
--    select c.code, c.full_name, ch.aircraft_type, ch.total_hours
--      from crew_hours ch join crew_members c on c.id = ch.crew_member_id
--     order by ch.total_hours desc;
-- =====================================================================
