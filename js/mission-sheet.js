// =====================================================================
//  mission-sheet.js — วาดการ์ดภารกิจแบบกระดานจัดบิน (ใช้ร่วม: หน้าหลัก + หน้าภารกิจรายวัน)
//  คู่กับ css/sheet.css
// =====================================================================
import { KINDS, DEFAULT_KIND, kindStyle, PILOT_ROLES, OTHER_ROLES, acLabel, esc, reportOf, deleteMission } from "./missions.js";

// ---------- แถวลูกเรือ ----------
// ตำแหน่งที่ไม่มีคน → ไม่แสดงแถวเลย
function crewRow(role, crew) {
  const names = crew.filter(c => (c.position||"").toUpperCase() === role)
                    .sort((a,b)=>(a.sort_order||0)-(b.sort_order||0))
                    .map(c => (c.crew_name || "").trim())
                    .filter(Boolean);
  if (!names.length) return "";
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
