# CLAUDE.md — คู่มือสำหรับ AI agent (และคน) ที่มาพัฒนาต่อ

> ไฟล์นี้อยู่ในโฟลเดอร์ `cowork/` · path ทั้งหมดในเอกสารอ้างอิงจาก **root ของ repo** (โฟลเดอร์แม่ `../`)
> อ่านไฟล์นี้ก่อนเริ่มทำงานทุกครั้ง แล้วอ่าน **[WORKLOG.md](WORKLOG.md)** เพื่อดูว่ามีใครแก้อะไรไปแล้วบ้าง
> ภาพรวมสถาปัตยกรรมแบบมองเห็นภาพ (flow chart) อยู่ที่ **[../architecture.html](../architecture.html)**

---

## 1. โปรเจกต์นี้คืออะไร

**Flight Operation** — เว็บจัดบินรายวันของฝูงบิน (ฝูง.603 บน.6) สำหรับผู้ใช้ ~100 คน
จัดภารกิจ · คิวบิน · สถานภาพเครื่อง · รายงานหลังบิน · ชั่วโมงบินสะสม · ความพร้อมบิน (currency) · สถิติ

- **Live:** https://greensupawich.github.io/flight-operation/
- **Repo:** `greensupawich/flight-operation` (branch `main`)
- **Local path:** `~/Documents/Claude/Code/flight-operation`

## 2. เทคโนโลยี (ไม่มี build step / ไม่มี framework)

- **Frontend:** Vanilla JS (ES Modules, `import` ตรง), HTML5, CSS (variables + ธีมสว่าง/มืด)
- **Backend:** Supabase — PostgreSQL + Auth (Google OAuth) + **RLS** + Triggers (PL/pgSQL)
- **Hosting:** GitHub Pages (static) · deploy = `git push` → build ~1 นาที
- **SDK:** `@supabase/supabase-js@2` โหลดจาก `esm.sh` CDN (ดู `js/supabase.js`)
- **Supabase project ref:** `iljapjszrjuzjjbtxctu`

## 3. โครงสร้างไฟล์

```
*.html            12 หน้า (index, pending, home, day, dashboard, mission,
                  report, crew, queue, status, stats, admin)
js/*.js           14 module (supabase, auth, ui, missions, mission-sheet,
                  reports, crew, queue, queue-rank, availability, status,
                  admin, combobox, local-auth[เลิกใช้])
css/style.css     สไตล์กลาง · css/sheet.css การ์ดภารกิจ
db/*.sql          schema, policies, triggers + migration_01..22 + import_* + seed_*
static-server.cjs dev server (static)
architecture.html เอกสารสถาปัตยกรรม (self-contained)
```

หน้าหลักคือ `home.html` = กระดานจัดบินรายวัน (แผงสถานภาพเครื่องซ้าย + การ์ดภารกิจ 3 ใบ/แถว + STBY + น.จัดบิน) เลื่อนวันได้ + Export PDF

## 4. กฎการทำงาน (สำคัญมาก)

1. **commit + push ทุกครั้งที่แก้เสร็จ** — GitHub Pages deploy อัตโนมัติจาก `main`
   ปิดท้าย commit ด้วย: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
2. **บันทึกลง [WORKLOG.md](WORKLOG.md)** ทุกครั้งที่ทำงานเสร็จ (ดูรูปแบบในไฟล์นั้น)
3. **ตรวจ JS syntax ก่อน commit** (โค้ดอยู่ใน `<script type="module">` ในไฟล์ .html):
   ```bash
   awk '/<script type="module">/{f=1;next} /<\/script>/{f=0} f' PAGE.html | node --input-type=module --check -
   ```
4. **ไฟล์ SQL รันเองไม่ได้** — ต้องให้ผู้ใช้ไปรันใน **Supabase → SQL Editor** เอง
   เขียน migration/seed/import ให้ **รันซ้ำได้ปลอดภัย (idempotent)** เสมอ
5. **verify ในเบราว์เซอร์** ทำได้จำกัด เพราะทุกหน้า (ยกเว้น architecture.html) ต้องล็อกอิน Google —
   ตรวจได้แค่ว่าโหลดแล้วไม่มี console error (จะ redirect ไป index)

## 5. ฐานข้อมูล & สิทธิ์ (RLS)

- helper: `is_active()` · `can_plan()` (admin/planner) · `is_admin()`
- role enum: `admin, planner, pilot, crew, viewer` · status: `pending, active, disabled`
- ผู้ใช้คนแรก = admin+active อัตโนมัติ (trigger `handle_new_user`) · คนถัดไป = pending/viewer รออนุมัติ
- **anon key ใน `js/supabase.js` ปลอดภัย** (ป้องกันด้วย RLS) — อย่าใส่ service-role key ในโค้ด
- ตารางส่วนใหญ่: อ่าน = `is_active`, เขียน = `can_plan` · ดู matrix เต็มใน architecture.html §7

### กลไกอัตโนมัติ (triggers) — อย่าคิดคำนวณเองในแอป
- บันทึก `post_flight_reports` → กระจาย **ชม.บิน** ไป `crew_hours` + `aircraft.total_hours`,
  อัปเดต **currency** `crew_members.last_500/600_date` (trigger `bump_crew_currency`), และ `discrepancies`
- แก้ `aircraft.status` → บันทึกประวัติลง `aircraft_status_history` (snapshot รายวัน)

## 6. กับดักที่เคยพลาด (อ่านก่อนแตะ SQL)

- `missions.status` เป็น **enum** `mission_status` — ห้าม `coalesce(m.status,'')` (ใช้ `is distinct from 'cancelled'`)
- **ห้ามรันซ้ำ** `migration_03` (สร้างทะเบียนซ้ำ) และ `migration_08` (ย้อนกฎ admin)
- import ภารกิจจับคู่นักบิน **ด้วยชื่อ** (helper `match_pilot`: ตัดช่องว่าง → alias → ชื่อล้วนถ้าไม่ซ้ำ) —
  ชื่อสะกดต่างจากทะเบียนจะถูกข้าม ให้โชว์ผล ✓/✗ ต่อคนเสมอ
- นำเข้ากระดานจัดบิน 1 วัน = `import_missions_YYYY_MM_DD.sql` + `import_aircraft_status_YYYY_MM_DD.sql`
- **บล็อก STBY:** ชื่อที่อยู่ใต้ลูกเรือ STBY คือ **น.จัดบินของวันนั้น** (ไม่ใช่ POC ของ STBY)
- `day_notes` เก็บ น.จัดบิน 1 แถว/วัน · หน้า home อ่าน "วันนี้" + "พรุ่งนี้" (แถวของวันถัดไป)

## 7. รันในเครื่อง

```bash
node static-server.cjs      # → http://localhost:5510
```
พอร์ต **5510 จำเป็น** สำหรับ OAuth (ต้องมี `http://localhost:5510/**` ใน Supabase → Auth → Redirect URLs)

## 8. เริ่มงานยังไง

1. อ่าน `cowork/CLAUDE.md` (ไฟล์นี้) + `cowork/WORKLOG.md`
2. เปิด `architecture.html` (ที่ root) เพื่อเห็นภาพรวม + รายชื่อ 19 ตาราง
3. หาไฟล์ที่เกี่ยวข้อง (หน้า .html + js/ module + db/ ถ้าแตะฐานข้อมูล)
4. แก้ → ตรวจ syntax → commit+push → เขียน WORKLOG
