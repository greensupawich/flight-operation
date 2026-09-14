// =====================================================================
//  availability.js — นักบินแจ้ง "ไม่ว่าง" ของตัวเอง
// =====================================================================
import { supabase } from "./supabase.js";

// ชื่อในทะเบียนที่ผูกกับบัญชีที่ล็อกอินอยู่ (null = ยังไม่ผูก)
export async function getMyCrewMember(profileId) {
  const { data } = await supabase.from("crew_members")
    .select("id,code,full_name,position").eq("profile_id", profileId).maybeSingle();
  return data || null;
}

export async function loadUnclaimedCrew() {
  const { data } = await supabase.from("crew_members")
    .select("id,code,full_name,position").eq("active", true).is("profile_id", null).order("code");
  return data || [];
}

export async function claimCrew(crewId) {
  const { error } = await supabase.rpc("claim_crew_member", { p_crew: crewId });
  return error;
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
