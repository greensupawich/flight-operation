// =====================================================================
//  missions.js — ปฏิทินภารกิจ + อ่าน/เขียนภารกิจ + ลูกเรือ
// =====================================================================
import { supabase } from "./supabase.js";

// ---------- ชนิดภารกิจ ----------
export const KINDS = {
  rtaf: "ทอ.", mod: "กห.", palace: "วัง", training: "ฝึกบิน", other: "อื่นๆ",
};

// ---------- ตำแหน่งลูกเรือ (เรียงตามฟอร์ม) ----------
export const PILOT_ROLES = ["AC", "IP", "P", "CP", "N"];
export const OTHER_ROLES = ["FM", "RO", "LM", "AH"];
export const CREW_ROLES  = [...PILOT_ROLES, ...OTHER_ROLES];
// AC และ N ไม่นับ ชม.บิน
export const NO_HOURS_ROLES = ["AC", "N"];

const MISSION_SELECT =
  "*, aircraft(id,tail_number,type), mission_crew(id,position,crew_name,crew_member_id,sort_order)";

// =====================================================================
//  ปฏิทิน — นับจำนวนภารกิจต่อวันในเดือนที่กำหนด
//  คืน { "2026-09-11": 3, ... }
// =====================================================================
export async function loadMonthCounts(year, month /* 0-11 */) {
  const first = new Date(Date.UTC(year, month, 1));
  const last  = new Date(Date.UTC(year, month + 1, 0));
  const { data, error } = await supabase
    .from("missions")
    .select("mission_date")
    .gte("mission_date", iso(first))
    .lte("mission_date", iso(last));
  if (error) { console.error(error); return {}; }
  const counts = {};
  (data || []).forEach((r) => { counts[r.mission_date] = (counts[r.mission_date] || 0) + 1; });
  return counts;
}

// ---------- ภารกิจทั้งหมดของวันหนึ่ง (พร้อมลูกเรือ) ----------
export async function loadMissionsByDate(dateStr) {
  const { data, error } = await supabase
    .from("missions").select(MISSION_SELECT)
    .eq("mission_date", dateStr)
    .order("created_at", { ascending: true });
  if (error) { console.error(error); return []; }
  return data || [];
}

export async function getMission(id) {
  const { data, error } = await supabase
    .from("missions").select(MISSION_SELECT).eq("id", id).single();
  if (error) { console.error(error); return null; }
  return data;
}

// =====================================================================
//  บันทึกภารกิจ (สร้างใหม่ถ้าไม่มี id) + แทนที่รายชื่อลูกเรือทั้งชุด
//  crew = [{ position, crew_name, crew_member_id }]
// =====================================================================
export async function saveMission(id, fields, crew) {
  const { data: { session } } = await supabase.auth.getSession();
  let missionId = id;

  if (missionId) {
    const { error } = await supabase.from("missions").update(fields).eq("id", missionId);
    if (error) return { error };
  } else {
    const { data, error } = await supabase.from("missions")
      .insert({ ...fields, created_by: session?.user?.id }).select("id").single();
    if (error) return { error };
    missionId = data.id;
  }

  // แทนที่ลูกเรือทั้งชุด (ลบของเดิมแล้วใส่ใหม่ — ง่ายและตรงกับฟอร์ม)
  const { error: delErr } = await supabase.from("mission_crew").delete().eq("mission_id", missionId);
  if (delErr) return { error: delErr, id: missionId };

  const rows = (crew || [])
    .filter((c) => c.crew_name && c.crew_name.trim())
    .map((c, i) => ({
      mission_id: missionId,
      position: c.position,
      crew_name: c.crew_name.trim(),
      crew_member_id: c.crew_member_id || null,
      sort_order: i,
    }));

  if (rows.length) {
    const { error } = await supabase.from("mission_crew").insert(rows);
    if (error) return { error, id: missionId };
  }
  return { id: missionId };
}

export async function deleteMission(id) {
  const { error } = await supabase.from("missions").delete().eq("id", id);
  return error;
}

// ---------- เครื่องบิน (รายการตายตัว 6 ลำ — seed ไว้ใน migration_02) ----------
export async function loadAircraft() {
  const { data } = await supabase.from("aircraft").select("id,tail_number,type").order("tail_number");
  return data || [];
}

// ชื่อที่แสดง เช่น "ATR72-600/60301"
export const acLabel = (a) => a ? `${a.type || ""}/${a.tail_number}` : "-";

// ---------- ทะเบียนลูกเรือ (ไว้เลือกตอนจัดลูกเรือ — ชม.บินผูกกับรหัสในทะเบียน) ----------
export async function loadCrewRoster() {
  const { data } = await supabase.from("crew_members")
    .select("id,code,full_name,position").eq("active", true).order("full_name");
  return data || [];
}

// ---------- helper ----------
export const iso = (d) =>
  `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;

export const isoLocal = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export function esc(s) {
  return String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}
