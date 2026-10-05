-- =====================================================================
--  Flight Operation · import_aircraft_status_2026_10_01_05.sql
--  สถานภาพเครื่อง 1–5 ต.ค. 2569 จากไฟล์ "จัดบิน ฝูง.603 3-5 ต.ค.69 แก้ไขครั้งที่ 2.xlsx"
--   • บันทึกประวัติสถานภาพ (aircraft_status_history) ของทุกวัน 1–5 ต.ค.
--   • สถานภาพปัจจุบัน + ข้อขัดข้อง + รายการเช็ค = ตามกระดานวันที่ 5 ต.ค.
--   • 1–4 ต.ค. เหมือนกันทุกเครื่อง · 5 ต.ค. เครื่อง 302 เปลี่ยนเป็น NMC (รอพัสดุ ล้อ Nose)
--   • NMCS ในกระดาน → เก็บเป็น NMC · ใส่ NMCS ไว้ในหมายเหตุ
--   • รันซ้ำได้ · ต้องรัน migration_17, 18, 19 ก่อน
--  รันใน Supabase → SQL Editor
-- =====================================================================
do $$
declare v_id uuid;
begin

  -- ===== ประวัติสถานภาพ 2026-10-01 =====
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-01', 'FMC', null from public.aircraft where tail_number = '60313'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-01', 'NMC', 'สถานภาพเดิม: NMCS' from public.aircraft where tail_number = '60315'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-01', 'FMC', null from public.aircraft where tail_number = '60316'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-01', 'NMC', null from public.aircraft where tail_number = '60301'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-01', 'FMC', null from public.aircraft where tail_number = '60302'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-01', 'FMC', null from public.aircraft where tail_number = '60303'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();

  -- ===== ประวัติสถานภาพ 2026-10-02 =====
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-02', 'FMC', null from public.aircraft where tail_number = '60313'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-02', 'NMC', 'สถานภาพเดิม: NMCS' from public.aircraft where tail_number = '60315'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-02', 'FMC', null from public.aircraft where tail_number = '60316'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-02', 'NMC', null from public.aircraft where tail_number = '60301'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-02', 'FMC', null from public.aircraft where tail_number = '60302'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-02', 'FMC', null from public.aircraft where tail_number = '60303'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();

  -- ===== ประวัติสถานภาพ 2026-10-03 =====
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-03', 'FMC', null from public.aircraft where tail_number = '60313'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-03', 'NMC', 'สถานภาพเดิม: NMCS' from public.aircraft where tail_number = '60315'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-03', 'FMC', null from public.aircraft where tail_number = '60316'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-03', 'NMC', null from public.aircraft where tail_number = '60301'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-03', 'FMC', null from public.aircraft where tail_number = '60302'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-03', 'FMC', null from public.aircraft where tail_number = '60303'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();

  -- ===== ประวัติสถานภาพ 2026-10-04 =====
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-04', 'FMC', null from public.aircraft where tail_number = '60313'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-04', 'NMC', 'สถานภาพเดิม: NMCS' from public.aircraft where tail_number = '60315'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-04', 'FMC', null from public.aircraft where tail_number = '60316'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-04', 'NMC', null from public.aircraft where tail_number = '60301'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-04', 'FMC', null from public.aircraft where tail_number = '60302'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-04', 'FMC', null from public.aircraft where tail_number = '60303'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();

  -- ===== ประวัติสถานภาพ 2026-10-05 =====
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-05', 'FMC', null from public.aircraft where tail_number = '60313'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-05', 'NMC', 'สถานภาพเดิม: NMCS' from public.aircraft where tail_number = '60315'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-05', 'FMC', null from public.aircraft where tail_number = '60316'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-05', 'NMC', null from public.aircraft where tail_number = '60301'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-05', 'NMC', null from public.aircraft where tail_number = '60302'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
  insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
  select id, '2026-10-05', 'FMC', null from public.aircraft where tail_number = '60303'
  on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();

  -- ===== 60313 (FMC) — ปัจจุบัน ตามกระดาน 2026-10-05 =====
  select id into v_id from public.aircraft where tail_number = '60313';
  if v_id is not null then
    update public.aircraft set status = 'FMC', status_note = null where id = v_id;
    insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
    values (v_id, '2026-10-05', 'FMC', null)
    on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
    delete from public.aircraft_defects where aircraft_id = v_id;
    delete from public.aircraft_checks where aircraft_id = v_id;
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 1, '2 M', '24 - 25 พ.ย.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 2, 'A12-Cx', '26 - 27 ม.ค.70');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 3, 'C-Cx', '1 มิ.ย. - 1 ส.ค.70');
  end if;

  -- ===== 60315 (NMCS) — ปัจจุบัน ตามกระดาน 2026-10-05 =====
  select id into v_id from public.aircraft where tail_number = '60315';
  if v_id is not null then
    update public.aircraft set status = 'NMC', status_note = 'สถานภาพเดิม: NMCS' where id = v_id;
    insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
    values (v_id, '2026-10-05', 'NMC', 'สถานภาพเดิม: NMCS')
    on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
    delete from public.aircraft_defects where aircraft_id = v_id;
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 1, 'LH Propeller Assembly ครบตรวจ Overhaul');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 2, 'RH.Propeller Anti Icing Fault (รอเคลมจาก TAI)');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 3, 'NLG Shock Absorber Leak รอพัสดุ จำนวน 7 รายการ');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 4, 'MLG Shock Absorber LH. Leak รอส่งซ่อม');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 5, 'MLG Shock Absorber RH. Leak ต้องการพัสดุ จำนวน 5 รายการ');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 6, 'Fuel Flow IND. Fuel Used Not Show ต้องการพัสดุ จำนวน 1 รายการ');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 7, 'ITT Eng.1 มีแนวโน้มสูง ต้องการพัสดุ 3 รายการ');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 8, 'ฝกช. CANN. พัสดุเพื่อนำไปแก้ไขข้อขัดข้อง จำนวน 249 รายการ');
    delete from public.aircraft_checks where aircraft_id = v_id;
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 1, '2 M', '20 - 21 ต.ค.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 2, 'A7-Cx', '20 - 21 ต.ค.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 3, 'C-Cx', '18 ส.ค. - 18 ต.ค.71');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 4, 'HANGAR QUEEN', null);
  end if;

  -- ===== 60316 (FMC) — ปัจจุบัน ตามกระดาน 2026-10-05 =====
  select id into v_id from public.aircraft where tail_number = '60316';
  if v_id is not null then
    update public.aircraft set status = 'FMC', status_note = null where id = v_id;
    insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
    values (v_id, '2026-10-05', 'FMC', null)
    on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
    delete from public.aircraft_defects where aircraft_id = v_id;
    delete from public.aircraft_checks where aircraft_id = v_id;
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 1, '2 M', '14 - 15 ต.ค.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 2, 'A1-Cx', '14 - 15 ต.ค.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 3, 'C-Cx', '15 มิ.ย. - 15 ส.ค.73');
  end if;

  -- ===== 60301 (NMC) — ปัจจุบัน ตามกระดาน 2026-10-05 =====
  select id into v_id from public.aircraft where tail_number = '60301';
  if v_id is not null then
    update public.aircraft set status = 'NMC', status_note = null where id = v_id;
    insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
    values (v_id, '2026-10-05', 'NMC', null)
    on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
    delete from public.aircraft_defects where aircraft_id = v_id;
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 1, 'LH. & RH. Propeller Assembly ครบตรวจ Overhaul');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 2, 'LH. Leading Edge ชำรุด');
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 3, 'Pressure Switch P/N P18M-H143 ห้องน้ำ VIP ชำรุด');
    delete from public.aircraft_checks where aircraft_id = v_id;
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 1, '2 M', '9 - 10 พ.ย.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 2, 'A12-Cx', '4 - 5 ม.ค.70');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 3, 'C-Cx', '4 ม.ค. - 4 มี.ค.70');
  end if;

  -- ===== 60302 (NMC) — ปัจจุบัน ตามกระดาน 2026-10-05 =====
  select id into v_id from public.aircraft where tail_number = '60302';
  if v_id is not null then
    update public.aircraft set status = 'NMC', status_note = null where id = v_id;
    insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
    values (v_id, '2026-10-05', 'NMC', null)
    on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
    delete from public.aircraft_defects where aircraft_id = v_id;
    insert into public.aircraft_defects (aircraft_id, seq, description) values (v_id, 1, 'รอพัสดุ ล้อ Nose');
    delete from public.aircraft_checks where aircraft_id = v_id;
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 1, '2 M', '17 - 18 พ.ย.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 2, 'A11-Cx', '18 - 19 ม.ค.70');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 3, 'C-Cx', '1 เม.ย.- 4 มิ.ย.70');
  end if;

  -- ===== 60303 (FMC) — ปัจจุบัน ตามกระดาน 2026-10-05 =====
  select id into v_id from public.aircraft where tail_number = '60303';
  if v_id is not null then
    update public.aircraft set status = 'FMC', status_note = null where id = v_id;
    insert into public.aircraft_status_history (aircraft_id, log_date, status, note)
    values (v_id, '2026-10-05', 'FMC', null)
    on conflict (aircraft_id, log_date) do update set status = excluded.status, note = excluded.note, updated_at = now();
    delete from public.aircraft_defects where aircraft_id = v_id;
    delete from public.aircraft_checks where aircraft_id = v_id;
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 1, '2 M', '27 - 28 ต.ค.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 2, 'A10-Cx', '23 - 24 ธ.ค.69');
    insert into public.aircraft_checks (aircraft_id, seq, name, due_text) values (v_id, 3, 'C-Cx', '2 ส.ค. - 2 ต.ค.70');
  end if;

end $$;

select a.tail_number as "เครื่อง", a.status as "สถานภาพ",
       (select count(*) from aircraft_defects d where d.aircraft_id=a.id) as "ข้อขัดข้อง",
       (select count(*) from aircraft_checks c where c.aircraft_id=a.id) as "รายการเช็ค"
  from public.aircraft a order by a.tail_number;
