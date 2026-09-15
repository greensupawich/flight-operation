// =====================================================================
//  availability.js — นักบินที่ไม่ว่าง (หน้าวัน)
// =====================================================================
import { supabase } from "./supabase.js";
import { loadAliasMap } from "./missions.js";

// นักบินทุกคนในทะเบียน (ที่ใช้งานอยู่) — ไว้เลือกในช่องเพิ่มคนไม่ว่าง
export async function loadRoster() {
  const [{ data }, aliases] = await Promise.all([
    supabase.from("crew_members").select("id,code,full_name,position").eq("active", true).order("code"),
    loadAliasMap(),
  ]);
  return (data || []).map((c) => ({ ...c, aliases: aliases?.get(c.id) || [] }));
}

// ใครไม่ว่างวันนี้บ้าง
export async function loadUnavailableOn(date) {
  const { data } = await supabase.from("crew_unavailable")
    .select("crew_member_id,note,crew_members(code,full_name,position)")
    .eq("off_date", date);
  return (data || []).sort((a, b) => String(a.crew_members?.code).localeCompare(String(b.crew_members?.code)));
}

export async function setUnavailable(crewId, date, note) {
  const { error } = await supabase.from("crew_unavailable")
    .upsert({ crew_member_id: crewId, off_date: date, note: (note || "").trim() || null },
            { onConflict: "crew_member_id,off_date" });
  return error;
}

export async function clearUnavailable(crewId, date) {
  const { error } = await supabase.from("crew_unavailable")
    .delete().eq("crew_member_id", crewId).eq("off_date", date);
  return error;
}
