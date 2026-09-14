// =====================================================================
//  crew.js — ทะเบียนลูกเรือ
//  รหัส (code) = ตัวระบุตัวตนถาวร · เปลี่ยนชื่อ/ยศได้โดย ชม.บินไม่หาย
// =====================================================================
import { supabase } from "./supabase.js";

export async function loadCrew(includeInactive = true) {
  let q = supabase.from("crew_members").select("*").order("code");
  if (!includeInactive) q = q.eq("active", true);
  const { data, error } = await q;
  if (error) { console.error(error); return []; }
  return data || [];
}

// เพิ่มคนใหม่ — รหัสห้ามซ้ำ
export async function addCrew({ code, full_name, position, note }) {
  const { error } = await supabase.from("crew_members")
    .insert({ code: code.trim(), full_name: full_name.trim(),
              position: (position || "").trim() || null, note: (note || "").trim() || null });
  return error;
}

// แก้ไข — แก้ชื่อ/ยศได้ตามใจ ชม.บินยังผูกกับคนเดิมเพราะยึด id ภายใน
export async function updateCrew(id, fields) {
  const { error } = await supabase.from("crew_members").update(fields).eq("id", id);
  return error;
}

export async function deleteCrew(id) {
  const { error } = await supabase.from("crew_members").delete().eq("id", id);
  return error;
}

// =====================================================================
//  สถิติประจำเดือนของนักบิน — จากภารกิจที่บินในเดือนนั้น (ภารกิจที่มีรายงานหลังบินแล้ว)
//   • flights = จำนวนเที่ยวบิน: นับทุกตำแหน่งนักบิน (AC / IP / P / CP / N)
//   • hours   = ชม.บิน: นับเฉพาะ IP / P / CP (AC และ N ไม่นับ ชม.)
//   คนเดียวหลายตำแหน่งในภารกิจเดียว นับเป็น 1 เที่ยว
//  คืน { crew_member_id: { hours, flights } }
// =====================================================================
const PILOT_POSITIONS = ["AC", "IP", "P", "CP", "N"];
const HOUR_POSITIONS  = ["IP", "P", "CP"];

export async function loadMonthlyStats(year, month /* 0-11 */) {
  const pad = (n) => String(n).padStart(2, "0");
  const first = `${year}-${pad(month + 1)}-01`;
  const last  = `${year}-${pad(month + 1)}-${pad(new Date(year, month + 1, 0).getDate())}`;

  const { data, error } = await supabase
    .from("mission_crew")
    .select("crew_member_id, position, mission_id, missions!inner(mission_date, post_flight_reports(total_hours))")
    .not("crew_member_id", "is", null)
    .gte("missions.mission_date", first)
    .lte("missions.mission_date", last);
  if (error) { console.error(error); return {}; }

  // รวมตำแหน่งของแต่ละคนต่อภารกิจก่อน (กันนับซ้ำ)
  const perMission = new Map();   // "member|mission" -> { member, positions:Set, report }
  (data || []).forEach((r) => {
    const pos = String(r.position || "").trim().toUpperCase();
    if (!PILOT_POSITIONS.includes(pos)) return;
    const rep = r.missions?.post_flight_reports;            // 1 ภารกิจ = 1 รายงาน (object หรือ array)
    const report = Array.isArray(rep) ? rep[0] : rep;
    if (!report) return;                                     // ยังไม่มีรายงาน = ยังไม่ถือว่าบินแล้ว
    const key = `${r.crew_member_id}|${r.mission_id}`;
    if (!perMission.has(key)) perMission.set(key, { member: r.crew_member_id, positions: new Set(), report });
    perMission.get(key).positions.add(pos);
  });

  const by = {};
  perMission.forEach(({ member, positions, report }) => {
    const st = by[member] || (by[member] = { hours: 0, flights: 0 });
    st.flights += 1;
    if ([...positions].some((p) => HOUR_POSITIONS.includes(p))) st.hours += Number(report.total_hours || 0);
  });
  return by;
}
