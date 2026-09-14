// =====================================================================
//  queue-rank.js — คำนวณลำดับคิวบิน (ไม่มีการเรียกฐานข้อมูล ทดสอบแยกได้)
//
//  กลุ่ม: IP + P นับรวมกัน · CP นับแยก
//  ลำดับ: 1) บินจริงน้อยสุด (ไม่นับ ST / ไม่นับเที่ยวที่บินในวันหยุด) ในเดือนนั้น
//         2) บินจริงครั้งล่าสุดนานกว่า (ไม่เคยบิน = นานสุด)
//         3) ชื่ออยู่บนกว่า (ลำดับในทะเบียน)
//  ไม่ได้คิว: ไม่ได้ติ๊ก / ไม่ว่างในวันนั้น / มีรายการในวันนั้นแล้ว / ไม่มีคุณวุฒิ
// =====================================================================
const pad = (n) => String(n).padStart(2, "0");
export const fmtDate = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
export const addDays = (s, n) => { const d = new Date(s + "T00:00:00"); d.setDate(d.getDate() + n); return fmtDate(d); };
export const isWeekend = (s) => { const w = new Date(s + "T00:00:00").getDay(); return w === 0 || w === 6; };

// วันทำการถัดไป: พรุ่งนี้ · ศุกร์ → จันทร์ · ข้ามเสาร์-อาทิตย์และวันหยุดราชการ
export function nextWorkingDay(todayStr, isOff) {
  let d = todayStr;
  for (let i = 0; i < 60; i++) {
    d = addDays(d, 1);
    if (!isOff(d)) return d;
  }
  return addDays(todayStr, 1);
}

export const queueGroup = (position) =>
  position === "CP" ? "CP" : (position === "IP" || position === "P") ? "IPP" : null;

/**
 * @param crew        [{id, position, in_queue}] เรียงตามลำดับในตาราง
 * @param monthDates  วันที่ทั้งหมดของเดือนที่แสดงคิว
 * @param target      วันที่แสดงคิว
 * @param isOff       (date) => วันหยุด?
 * @param itemsFor    (crewId, date) => [{st:boolean}]   สิ่งที่อยู่ในช่อง
 * @param isUnavailable (crewId, date) => boolean
 * @param historyStart  วันแรกที่ใช้ค้นหา "บินล่าสุด"
 * @returns Map(crewId -> { group, rank|null, flights, last|null, reason|null })
 */
export function rankQueue({ crew, monthDates, target, isOff, itemsFor, isUnavailable, historyStart }) {
  const result = new Map();
  const groups = { IPP: [], CP: [] };

  crew.forEach((p, idx) => {
    const group = queueGroup(p.position);
    if (!group) return;
    const realOn = (d) => itemsFor(p.id, d).some((it) => !it.st);

    const flights = monthDates.reduce((n, d) =>
      n + (isOff(d) ? 0 : itemsFor(p.id, d).filter((it) => !it.st).length), 0);

    let last = null;
    for (let d = addDays(target, -1); d >= historyStart; d = addDays(d, -1)) {
      if (realOn(d)) { last = d; break; }
    }

    let reason = null;
    if (p.in_queue === false) reason = "ไม่ได้ติ๊กนับคิว";
    else if (isUnavailable(p.id, target)) reason = "ไม่ว่าง";
    else if (itemsFor(p.id, target).length) reason = "มีรายการในวันนั้นแล้ว";

    const row = { id: p.id, idx, group, flights, last, reason, rank: null };
    groups[group].push(row);
    result.set(p.id, row);
  });

  for (const g of Object.values(groups)) {
    g.filter((r) => !r.reason)
     .sort((a, b) => a.flights - b.flights
                  || (a.last || "").localeCompare(b.last || "")   // ไม่เคยบิน ("") มาก่อน
                  || a.idx - b.idx)
     .forEach((r, i) => { r.rank = i + 1; });
  }
  return result;
}
