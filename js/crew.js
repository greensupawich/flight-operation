// =====================================================================
//  crew.js — ทะเบียนลูกเรือ
//  รหัส (code) = ตัวระบุตัวตนถาวร · เปลี่ยนชื่อ/ยศได้โดย ชม.บินไม่หาย
// =====================================================================
import { supabase } from "./supabase.js";

export async function loadCrew(includeInactive = true) {
  let q = supabase.from("crew_members").select("*").order("full_name");
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

// ชม.บินสะสมของแต่ละคน (ไว้โชว์ในทะเบียน)
export async function loadCrewHours() {
  const { data } = await supabase.from("crew_hours")
    .select("crew_member_id, aircraft_type, total_hours");
  const by = {};
  (data || []).forEach((r) => {
    if (!r.crew_member_id) return;
    by[r.crew_member_id] = (by[r.crew_member_id] || 0) + Number(r.total_hours || 0);
  });
  return by;
}
