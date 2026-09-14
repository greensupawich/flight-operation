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
//  ชม.บินประจำเดือน — รวม ชม.จากรายงานหลังบินของภารกิจที่บินในเดือนนั้น
//  นับเฉพาะ IP / P / CP (AC และ N ไม่นับ) · คนเดียวหลายตำแหน่งในภารกิจเดียวนับครั้งเดียว
//  คืน { crew_member_id: ชม. }
// =====================================================================
export async function loadMonthlyHours(year, month /* 0-11 */) {
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

  const seen = new Set(), by = {};
  (data || []).forEach((r) => {
    if (!["IP", "P", "CP"].includes(String(r.position || "").trim().toUpperCase())) return;
    const key = `${r.crew_member_id}|${r.mission_id}`;
    if (seen.has(key)) return;
    seen.add(key);
    const rep = r.missions?.post_flight_reports;          // 1 ภารกิจ = 1 รายงาน (อาจมาเป็น object หรือ array)
    const h = Array.isArray(rep) ? rep[0]?.total_hours : rep?.total_hours;
    by[r.crew_member_id] = (by[r.crew_member_id] || 0) + Number(h || 0);
  });
  return by;
}
