-- =====================================================================
--  Flight Operation · migration_21_crew_currency.sql
--  ความพร้อมบิน (currency) รายคน แยกแบบเครื่อง 500 / 600
--   • can_fly_500 / can_fly_600 — บินแบบนั้นได้ไหม (แก้ได้เฉพาะ admin/planner)
--   • last_500_date / last_600_date — วันบินล่าสุดของแบบนั้น (ใช้คิดสีเตือน 80/90 วัน)
--  รันซ้ำได้ ปลอดภัย
-- =====================================================================
alter table public.crew_members
  add column if not exists can_fly_500 boolean not null default true,
  add column if not exists can_fly_600 boolean not null default true,
  add column if not exists last_500_date date,
  add column if not exists last_600_date date;
