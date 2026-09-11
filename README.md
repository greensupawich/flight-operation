# 🛩️ Flight Operation — ระบบจัดบินรายวัน

เว็บจัดตารางบินสำหรับ ~100 ผู้ใช้ · ล็อกอิน Gmail · สิทธิ์รายคนที่ admin อนุมัติ · ต้นทุน ฿0

**สแตก:** Vanilla JS + HTML/CSS · Supabase (PostgreSQL + Auth + RLS) · GitHub Pages

---

## โครงสร้างไฟล์

```
flight-operation/
├── index.html        # หน้า login (Google)
├── pending.html      # หน้ารออนุมัติ
├── dashboard.html    # ภารกิจรายวัน
├── mission.html      # รายละเอียด + สร้างภารกิจ + จัดลูกเรือ
├── report.html       # รายงานหลังบิน + ขาบิน + ข้อขัดข้อง
├── admin.html        # อนุมัติผู้ใช้ + ให้สิทธิ์ (admin เท่านั้น)
├── stats.html        # สถิติ ชม.บิน / เครื่อง / ข้อขัดข้อง
├── css/style.css
├── js/
│   ├── supabase.js   # ⚙️ ใส่ URL + anon key ที่นี่
│   ├── auth.js       # login Google + ยามเฝ้าสิทธิ์
│   ├── ui.js         # แถบเมนู
│   ├── missions.js   # ภารกิจ
│   ├── reports.js    # รายงานหลังบิน
│   └── admin.js      # จัดการผู้ใช้
└── db/
    ├── schema.sql    # 1) สร้างตาราง
    ├── policies.sql  # 2) RLS สิทธิ์
    └── triggers.sql  # 3) กระจายข้อมูลอัตโนมัติ
```

---

## ติดตั้ง (ทั้งหมดฟรี)

### 1. สร้างฐานข้อมูล Supabase
1. สมัคร [supabase.com](https://supabase.com) → New Project (เลือก region สิงคโปร์)
2. เปิด **SQL Editor** → รันไฟล์ตามลำดับ: `db/schema.sql` → `db/policies.sql` → `db/triggers.sql`

### 2. เปิดล็อกอิน Google
1. [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials → สร้าง **OAuth Client ID** (Web)
2. Supabase → **Authentication → Providers → Google** → ใส่ Client ID/Secret → เปิดใช้งาน
3. คัดลอก redirect URL ที่ Supabase ให้ ไปใส่ใน Google OAuth (Authorized redirect URIs)
4. Supabase → **Authentication → URL Configuration** → ใส่ URL เว็บของคุณ (GitHub Pages) ใน Site URL + Redirect URLs

### 3. ตั้งค่าโค้ด
แก้ `js/supabase.js`:
```js
const SUPABASE_URL = "https://xxxxx.supabase.co";   // Project Settings → API
const SUPABASE_ANON_KEY = "eyJ....";                // anon public key (เปิดเผยได้)
```

### 4. Deploy ขึ้น GitHub Pages
```bash
git init && git add . && git commit -m "init flight operation"
git branch -M main
git remote add origin https://github.com/<user>/flight-operation.git
git push -u origin main
```
แล้วเปิด GitHub → Settings → Pages → Deploy from branch `main` / root

---

## บทบาท (Roles)

| role | สิทธิ์ |
|------|--------|
| `admin` | อนุมัติผู้ใช้ + ให้/เพิกถอนสิทธิ์ + จัดการทุกอย่าง |
| `planner` | สร้าง/แก้ภารกิจ + จัดลูกเรือ |
| `pilot` / `crew` | ดูภารกิจตัวเอง + กรอกรายงานไฟลท์ที่ตัวเองบิน |
| `viewer` | ดูอย่างเดียว (ค่าเริ่มต้นผู้ใช้ใหม่) |

> **ผู้ใช้คนแรก** ที่ล็อกอินจะถูกตั้งเป็น `admin` + `active` อัตโนมัติ (จาก trigger) เพื่อเริ่มให้สิทธิ์คนอื่นได้ — คนถัดไปเป็น `pending` + `viewer` รอ admin อนุมัติ

---

## ทดสอบ Phase 1 (เฉพาะฐานข้อมูล) ใน SQL Editor

```sql
-- เพิ่มเครื่อง
insert into aircraft(tail_number, type) values ('60101','EC725');
-- สร้างภารกิจ + ลูกเรือ + รายงานหลังบิน แล้วดูว่า crew_hours / aircraft.total_hours
-- ถูกอัปเดตอัตโนมัติจาก trigger
select * from crew_hours;
select tail_number, total_hours from aircraft;
```

---

## ความปลอดภัย
- ✅ RLS ทุกตาราง — บังคับสิทธิ์ที่ฐานข้อมูล ไม่ใช่แค่ frontend
- ✅ anon key เปิดเผยได้ (ทำได้แค่ที่ RLS อนุญาต) — **ห้ามใส่ service_role key ในโค้ดหน้าเว็บ**
- ✅ เฉพาะ admin แก้ `role`/`status` ได้ (บังคับด้วย trigger `guard_profile_privilege`)
- ✅ `crew_hours` เขียนผ่าน trigger เท่านั้น กันข้อมูลเพี้ยน
