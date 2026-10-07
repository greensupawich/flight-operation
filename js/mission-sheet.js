// =====================================================================
//  mission-sheet.js — วาดการ์ดภารกิจแบบกระดานจัดบิน (ใช้ร่วม: หน้าหลัก + หน้าภารกิจรายวัน)
//  คู่กับ css/sheet.css
// =====================================================================
import { KINDS, DEFAULT_KIND, kindStyle, PILOT_ROLES, OTHER_ROLES, acLabel, esc, reportOf, deleteMission } from "./missions.js";
import { supabase } from "./supabase.js";

// ---------- แถวลูกเรือ ----------
// ตำแหน่งที่ไม่มีคน → ไม่แสดงแถวเลย
function crewRow(role, crew) {
  const names = crew.filter(c => (c.position||"").toUpperCase() === role)
                    .sort((a,b)=>(a.sort_order||0)-(b.sort_order||0))
                    .map(c => (c.crew_name || "").trim())
                    .filter(Boolean);
  if (!names.length) return "";
  // AC มีคนเดียว → ใช้เต็มบรรทัด (ชื่อ + เบอร์ยาว ๆ ไม่ตัดขึ้นบรรทัดใหม่)
  if (role === "AC") return `<tr><td class="lb">${role}</td><td colspan="5" class="v">${names.map(esc).join(" · ")}</td></tr>`;
  const slots = Math.max(3, names.length);          // อย่างน้อย 3 ช่องให้ตรงกับกระดาน
  const cells = Array.from({length: slots}, (_, i) => `<span>${esc(names[i] || "")}</span>`).join("");
  return `<tr><td class="lb">${role}</td><td colspan="5" class="v">
            <div class="crewgrid">${cells}</div></td></tr>`;
}

export function sheetHTML(m, { planner = false } = {}) {
  const crew = m.mission_crew || [];
  const ac = m.aircraft ? acLabel(m.aircraft) : "";
  const poc = [m.poc_name, m.poc_phone].filter(Boolean).join("  ");
  const v = (x) => esc(x || "") || `<span class="muted-cell">-</span>`;
  // ยกเลิก (สถานะภารกิจจากผลในรายงาน) > รายงานแล้ว > ปกติ
  const state = m.status === "cancelled" ? "cancelled" : reportOf(m) ? "reported" : "";

  return `
  <div class="sheet ${state}" data-id="${m.id}">
    <div class="sheet-top" style="${kindStyle(m.kind)}">
      <span class="kind">${esc(KINDS[m.kind] || KINDS[DEFAULT_KIND])}</span>
      ${planner ? `<button type="button" class="drag-h" data-drag title="ลากเพื่อย้ายตำแหน่งการ์ด" aria-label="ลากเพื่อย้าย">⠿</button>` : ""}
      <span style="font-weight:700;font-size:13px">${esc(m.callsign || "-")}</span>
      <div class="sheet-actions">
        ${planner ? `<a class="btn sm" href="mission.html?id=${m.id}">แก้ไข</a>
                     <button class="btn sm" data-del style="color:var(--crit)">ลบ</button>` : ``}
        ${state === "cancelled"
          ? `<a class="btn sm rep-cancel" href="report.html?mission=${m.id}" title="ดู/แก้รายงาน">✕ ยกเลิก</a>`
          : state === "reported"
            ? `<a class="btn sm rep-done" href="report.html?mission=${m.id}" title="ดู/แก้รายงาน">✓ รายงานแล้ว</a>`
            : `<a class="btn sm accent" href="report.html?mission=${m.id}">รายงาน</a>`}
      </div>
    </div>
    <div class="sheet-body">
    <table class="fm">
      <colgroup><col style="width:17%"><col style="width:16%"><col style="width:17%">
                <col style="width:16%"><col style="width:17%"><col style="width:17%"></colgroup>
      <tr><td class="lb">A/C No.</td><td colspan="2" class="v c mono">${v(ac)}</td>
          <td class="lb">COWBOY</td><td colspan="2" class="v c mono">${v(m.callsign)}</td></tr>
      <tr><td class="lb">SHOWTIME</td><td colspan="2" class="v c mono">${v(m.showtime)}</td>
          <td class="lb">BRIEF</td><td colspan="2" class="v c mono">${v(m.brief_time)}</td></tr>
      <tr><td class="lb">STEP</td><td class="v c mono">${v(m.step_time)}</td>
          <td class="lb">TAXI</td><td class="v c mono">${v(m.taxi_time)}</td>
          <td class="lb">T/O</td><td class="v c mono">${v(m.takeoff_time)}</td></tr>
      <tr><td class="lb">ชพ.</td><td class="v c hot">${v(m.fuel)}</td>
          <td class="lb">จัดรับรอง</td><td class="v c hot">${v(m.catering)}</td>
          <td class="lb">PAX.</td><td class="v c hot">${v(m.pax)}</td></tr>
      <tr><td class="lb">ภารกิจ</td><td colspan="5" class="v c">${v(m.mission_name)}</td></tr>
      <tr><td class="lb">เส้นทางบิน</td><td colspan="5" class="v c">${v(m.route)}</td></tr>
      <tr><td class="lb">หน.คณะ</td><td colspan="5" class="v">${v(m.head_delegation)}</td></tr>
      ${[...PILOT_ROLES, ...OTHER_ROLES].map(r => crewRow(r, crew)).join("")}
      <tr><td class="lb">POCคณะ</td><td colspan="5" class="v">${v(poc)}</td></tr>
      <tr><td class="lb" rowspan="2">หมายเหตุ</td><td colspan="3" rowspan="2" class="v">${v(m.remark)}</td>
          <td class="lb">ไป</td><td class="v c hot">${v(m.parking_out)}</td></tr>
      <tr><td class="lb">กลับ</td><td class="v c hot">${v(m.parking_in)}</td></tr>
    </table>
    </div>
  </div>`;
}

// เรียงตามเวลา T/O · T/O เท่ากัน → BRIEF ที่มาก่อนอยู่ก่อน · แล้วค่อยตัดสินที่ callsign
// ภารกิจที่ T/O ไม่ใช่เวลา (STBY / ว่าง) อยู่ท้าย เรียงตาม BRIEF
export function sortByTakeoff(list) {
  const num = (s) => /^\d{3,4}$/.test(String(s || "").trim()) ? parseInt(s, 10) : null;
  const key = (m) => {
    const to = num(m.takeoff_time);
    const br = num(m.brief_time) ?? 9999;
    return to !== null ? [0, to, br] : [1, br, br];
  };
  return [...list].sort((a, b) => {
    const x = key(a), y = key(b);
    return x[0] - y[0] || x[1] - y[1] || x[2] - y[2]
        || String(a.callsign || "").localeCompare(String(b.callsign || ""));
  });
}

// ปุ่มลบในการ์ด (เฉพาะผู้วางแผน)
export function wireSheetDelete(container, onDone) {
  container.querySelectorAll("[data-del]").forEach((b) =>
    b.addEventListener("click", async (e) => {
      const id = e.target.closest(".sheet").dataset.id;
      if (!confirm("ลบภารกิจนี้? (ลบลูกเรือและรายงานที่ผูกอยู่ด้วย)")) return;
      b.disabled = true;
      const err = await deleteMission(id);
      if (err) { alert("ลบไม่สำเร็จ: " + err.message); b.disabled = false; }
      else onDone();
    }));
}

// =====================================================================
//  ลำดับการ์ดที่ผู้วางแผนจัดเอง (migration_29 · missions.display_order)
//   • มีการ์ดที่จัดลำดับแล้ว → เรียงตาม display_order ก่อน · ที่ยังไม่จัด (เพิ่มทีหลัง) ต่อท้ายตาม T/O
//   • ไม่มีเลย → เรียงตาม T/O (sortByTakeoff)
// =====================================================================
export const hasCustomOrder = (list) => list.some((m) => m.display_order != null);

export function orderMissions(list) {
  if (!hasCustomOrder(list)) return sortByTakeoff(list);
  const set = list.filter((m) => m.display_order != null).sort((a, b) => a.display_order - b.display_order);
  return [...set, ...sortByTakeoff(list.filter((m) => m.display_order == null))];
}

async function saveOrder(ids) {
  const res = await Promise.all(ids.map((id, i) =>
    supabase.from("missions").update({ display_order: i + 1 }).eq("id", id)));
  const err = res.find((r) => r.error)?.error;
  if (err && /display_order/.test(err.message)) return { message: "ต้องรัน migration_29_display_order.sql ก่อน" };
  return err || null;
}

// ล้างลำดับที่จัดเอง → กลับไปเรียงตาม T/O
export async function resetOrder(ids) {
  if (!ids.length) return null;
  const { error } = await supabase.from("missions").update({ display_order: null }).in("id", ids);
  return error;
}

// ลากวางการ์ด (จับที่ ⠿) · การ์ดแทรกตำแหน่งที่ลากไป การ์ดอื่นเลื่อนถัดไป
//  ใช้ pointer events → ได้ทั้งเมาส์และนิ้ว · ใช้ getBoundingClientRect จึงทำงานได้แม้กระดานถูก scale
//  onSaved(err) เรียกหลังบันทึกลำดับ
export function wireReorder(container, onSaved) {
  container.querySelectorAll("[data-drag]").forEach((h) => {
    h.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const card = h.closest(".sheet");
      const before = [...container.querySelectorAll(".sheet")].map((x) => x.dataset.id).join();
      card.classList.add("dragging");
      container.classList.add("reordering");
      // ฟังที่ window (ไม่ใช้ pointer capture — การย้ายการ์ดใน DOM ทำให้ capture หลุด)

      const move = (ev) => {
        const others = [...container.querySelectorAll(".sheet")].filter((x) => x !== card);
        for (const o of others) {
          const r = o.getBoundingClientRect();
          if (ev.clientX < r.left || ev.clientX > r.right || ev.clientY < r.top || ev.clientY > r.bottom) continue;
          // การ์ดเรียงหลายคอลัมน์ → ตัดสินด้วยครึ่งซ้าย/ขวา · คอลัมน์เดียว → ครึ่งบน/ล่าง
          const cw = container.getBoundingClientRect().width;
          const after = r.width < cw * 0.7 ? ev.clientX > r.left + r.width / 2 : ev.clientY > r.top + r.height / 2;
          const ref = after ? o.nextElementSibling : o;
          if (ref !== card && card.nextElementSibling !== ref) container.insertBefore(card, ref);
          break;
        }
        // ลากใกล้ขอบจอ → เลื่อนหน้าตาม
        if (ev.clientY < 60) scrollBy(0, -12); else if (ev.clientY > innerHeight - 60) scrollBy(0, 12);
      };
      const up = async () => {
        removeEventListener("pointermove", move);
        removeEventListener("pointerup", up);
        removeEventListener("pointercancel", up);
        card.classList.remove("dragging");
        container.classList.remove("reordering");
        const ids = [...container.querySelectorAll(".sheet")].map((x) => x.dataset.id);
        if (ids.join() === before) return;
        onSaved?.(await saveOrder(ids));
      };
      addEventListener("pointermove", move);
      addEventListener("pointerup", up);
      addEventListener("pointercancel", up);
    });
  });
}
