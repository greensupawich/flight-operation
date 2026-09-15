// =====================================================================
//  reports.js — รายงานหลังบิน + ขาการบิน + ข้อขัดข้อง
//  บันทึกรายงาน → trigger ในฐานข้อมูลกระจาย ชม. ไปลูกเรือ/เครื่องเอง
// =====================================================================
import { supabase } from "./supabase.js";

export async function getMission(id) {
  const { data } = await supabase
    .from("missions")
    .select("*, aircraft(tail_number,type), mission_crew(position, crew_name, sort_order)")
    .eq("id", id).single();
  return data;
}

// =====================================================================
//  แตก "เส้นทางบิน" เป็นขาการบิน
//   "บน.6 - บน.41 - บน.6"  →  [บน.6→บน.41, บน.41→บน.6]
//   ตัดวงเล็บเวลาออก เช่น "บน.1(0930)" → "บน.1"
// =====================================================================
export function routeToLegs(route) {
  if (!route) return [];
  const points = String(route)
    .split(/[-–—>→]+/)                 // รองรับทั้ง - – — > →
    .map((p) => p.replace(/\([^)]*\)/g, "").trim())   // ตัด (0930) ออก
    .filter(Boolean);
  const legs = [];
  for (let i = 0; i < points.length - 1; i++) {
    legs.push({ from_point: points[i], to_point: points[i + 1], hours: 0 });
  }
  return legs;
}

// ---------- ขาการบิน ----------
export async function loadLegs(missionId) {
  const { data } = await supabase.from("flight_legs")
    .select("*").eq("mission_id", missionId).order("leg_no");
  return data || [];
}

// แทนที่ขาทั้งชุด (ลำดับ = leg_no ตามที่เรียงบนหน้าจอ)
export async function replaceLegs(missionId, legs) {
  const { error: delErr } = await supabase.from("flight_legs").delete().eq("mission_id", missionId);
  if (delErr) return delErr;
  const rows = (legs || []).map((l, i) => ({
    mission_id: missionId,
    leg_no: i + 1,
    from_point: (l.from_point || "").trim(),
    to_point: (l.to_point || "").trim(),
    hours: Number(l.hours) || 0,
  }));
  if (!rows.length) return null;
  const { error } = await supabase.from("flight_legs").insert(rows);
  return error;
}

// ---------- รายงานหลังบิน (upsert: 1 ภารกิจ = 1 รายงาน) ----------
//  extra = { result: 'MCP'|'INCOMPLETE'|'CANCELLED'|null, parking_return }  (migration_16)
export async function saveReport(missionId, totalHours, remarks, extra = {}) {
  const { data: { session } } = await supabase.auth.getSession();
  const row = { mission_id: missionId, total_hours: totalHours, remarks, created_by: session?.user?.id,
                result: extra.result || null, parking_return: (extra.parking_return || "").trim() || null };
  let { error } = await supabase.from("post_flight_reports").upsert(row, { onConflict: "mission_id" });
  // ยังไม่ได้รัน migration_16 → บันทึกเฉพาะข้อมูลเดิม แล้วแจ้งเตือน
  if (error && /result|parking_return/.test(error.message)) {
    delete row.result; delete row.parking_return;
    ({ error } = await supabase.from("post_flight_reports").upsert(row, { onConflict: "mission_id" }));
    if (!error) return { warning: "บันทึก ชม.แล้ว แต่ผลภารกิจ/จุดจอดขากลับยังไม่ถูกเก็บ — ต้องรัน migration_16_report_result.sql" };
  }
  return error;
}

export async function getReport(missionId) {
  const { data } = await supabase.from("post_flight_reports")
    .select("*").eq("mission_id", missionId).maybeSingle();
  return data;
}

// ---------- ข้อขัดข้อง ----------
export async function loadDiscrepancies(missionId) {
  const { data } = await supabase.from("discrepancies")
    .select("*").eq("mission_id", missionId).order("created_at");
  return data || [];
}

export async function addDiscrepancy(missionId, aircraftId, description) {
  const { data: { session } } = await supabase.auth.getSession();
  const { error } = await supabase.from("discrepancies").insert({
    mission_id: missionId, aircraft_id: aircraftId, description, created_by: session?.user?.id,
  });
  return error;
}

export async function deleteDiscrepancy(id) {
  const { error } = await supabase.from("discrepancies").delete().eq("id", id);
  return error;
}
