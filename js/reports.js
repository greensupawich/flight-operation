// =====================================================================
//  reports.js — รายงานหลังบิน + ข้อขัดข้อง + ขาการบิน
//  บันทึกรายงาน → trigger ในฐานข้อมูลกระจาย ชม. ไปลูกเรือ/เครื่องเอง
// =====================================================================
import { supabase } from "./supabase.js";

export async function getMission(id) {
  const { data } = await supabase
    .from("missions")
    .select("*, aircraft(tail_number,type), mission_crew(profile_id, position, profiles(full_name,email))")
    .eq("id", id).single();
  return data;
}

// ---------- ขาการบิน ----------
export async function addLeg(missionId, leg) {
  const { error } = await supabase.from("flight_legs").insert({ mission_id: missionId, ...leg });
  if (error) alert("เพิ่มขาบินไม่สำเร็จ: " + error.message);
  return !error;
}
export async function loadLegs(missionId) {
  const { data } = await supabase.from("flight_legs").select("*").eq("mission_id", missionId).order("leg_no");
  return data || [];
}

// ---------- รายงานหลังบิน (upsert: 1 ภารกิจ = 1 รายงาน) ----------
export async function saveReport(missionId, totalHours, remarks) {
  const { data:{ session } } = await supabase.auth.getSession();
  const { error } = await supabase.from("post_flight_reports").upsert(
    { mission_id: missionId, total_hours: totalHours, remarks, created_by: session?.user?.id },
    { onConflict: "mission_id" }
  );
  if (error) { alert("บันทึกรายงานไม่สำเร็จ: " + error.message); return false; }
  return true;
}
export async function getReport(missionId) {
  const { data } = await supabase.from("post_flight_reports").select("*").eq("mission_id", missionId).maybeSingle();
  return data;
}

// ---------- ข้อขัดข้อง ----------
export async function addDiscrepancy(missionId, aircraftId, description) {
  const { data:{ session } } = await supabase.auth.getSession();
  const { error } = await supabase.from("discrepancies").insert({
    mission_id: missionId, aircraft_id: aircraftId, description, created_by: session?.user?.id,
  });
  if (error) { alert("บันทึกข้อขัดข้องไม่สำเร็จ: " + error.message); return false; }
  return true;
}
