// =====================================================================
//  queue.js — ข้อมูลหน้า "คิวบิน"
//  แถว = นักบินในทะเบียน · คอลัมน์ = วันที่ในเดือน
// =====================================================================
import { supabase } from "./supabase.js";

export const PILOT_POSITIONS = ["AC", "IP", "P", "CP", "N"];

const pad = (n) => String(n).padStart(2, "0");
export const monthRange = (y, m /* 0-11 */) => ({
  first: `${y}-${pad(m + 1)}-01`,
  last:  `${y}-${pad(m + 1)}-${pad(new Date(y, m + 1, 0).getDate())}`,
  days:  new Date(y, m + 1, 0).getDate(),
});

// ชื่อจุดในเส้นทาง → คีย์สำหรับค้นรหัส (ตัดวงเล็บเวลาและช่องว่างทั้งหมด)
export const airfieldKey = (name) => String(name || "").replace(/\([^)]*\)/g, "").replace(/\s+/g, "");

// จุดที่ 2 ของเส้นทาง "บน.6 - บน.41 - บน.6" → "บน.41"
export function secondPoint(route) {
  const pts = String(route || "").split(/[-–—>→]+/).map(airfieldKey).filter(Boolean);
  return pts[1] || pts[0] || "";
}

// ทะเบียนนักบิน + ช่องติ๊กนับคิว (ถ้ายังไม่ได้รัน migration_14 จะถือว่าติ๊กทุกคน)
async function loadCrewForQueue() {
  let r = await supabase.from("crew_members").select("id,code,full_name,position,in_queue").eq("active", true).order("code");
  if (r.error) r = await supabase.from("crew_members").select("id,code,full_name,position").eq("active", true).order("code");
  if (r.error) console.error(r.error);
  return r.data || [];
}

export async function setInQueue(crewId, value) {
  const { error } = await supabase.from("crew_members").update({ in_queue: value }).eq("id", crewId);
  return error;
}

// ข้อมูลย้อนหลัง (ไว้หา "บินจริงครั้งล่าสุด") และวันหยุดช่วงข้างหน้า (ไว้หาวันทำการถัดไป)
export async function loadHistory(first, last) {
  if (first > last) return { entries: [], missions: [] };
  const [e, m] = await Promise.all([
    supabase.from("queue_entries").select("crew_member_id,entry_date,code,kind,ac_type")
      .gte("entry_date", first).lte("entry_date", last),
    supabase.from("missions")
      .select("id,mission_date,kind,status,route,callsign,mission_name,aircraft(type,tail_number),mission_crew(crew_member_id,position)")
      .gte("mission_date", first).lte("mission_date", last),
  ]);
  return { entries: e.data || [], missions: m.data || [] };
}

export async function loadHolidaysBetween(first, last) {
  const { data } = await supabase.from("holidays").select("holiday_date,name")
    .gte("holiday_date", first).lte("holiday_date", last);
  return data || [];
}

export async function loadQueueMonth(y, m) {
  const { first, last } = monthRange(y, m);
  const [crew, missions, holidays, unavailable, airfields] = await Promise.all([
    loadCrewForQueue(),
    supabase.from("missions")
      .select("id,mission_date,kind,status,route,callsign,mission_name,aircraft(type,tail_number),mission_crew(crew_member_id,position)")
      .gte("mission_date", first).lte("mission_date", last),
    supabase.from("holidays").select("holiday_date,name").gte("holiday_date", first).lte("holiday_date", last),
    supabase.from("crew_unavailable").select("crew_member_id,off_date,note").gte("off_date", first).lte("off_date", last),
    supabase.from("airfields").select("name,code"),
  ]);
  for (const r of [missions, holidays, unavailable, airfields]) if (r.error) console.error(r.error);
  return {
    crew,
    missions: missions.data || [],
    holidays: holidays.data || [],
    unavailable: unavailable.data || [],
    airfields: airfields.data || [],
  };
}

// ---------- วันหยุด ----------
export async function setHoliday(date, name) {
  const { error } = await supabase.from("holidays").upsert({ holiday_date: date, name: name || null });
  return error;
}
export async function clearHoliday(date) {
  const { error } = await supabase.from("holidays").delete().eq("holiday_date", date);
  return error;
}

// ---------- วันไม่ว่าง (ทำทีละหลายช่องจากการลาก) ----------
export async function addUnavailable(crewId, dates, note) {
  if (!dates.length) return null;
  const row = (d) => note != null
    ? { crew_member_id: crewId, off_date: d, note: (note || "").trim() || null }
    : { crew_member_id: crewId, off_date: d };
  const { error } = await supabase.from("crew_unavailable")
    .upsert(dates.map(row), { onConflict: "crew_member_id,off_date" });
  return error;
}
export async function removeUnavailable(crewId, dates) {
  if (!dates.length) return null;
  const { error } = await supabase.from("crew_unavailable")
    .delete().eq("crew_member_id", crewId).in("off_date", dates);
  return error;
}

// ---------- รหัสสนามบิน ----------
export async function saveAirfield(name, code) {
  const { error } = await supabase.from("airfields")
    .upsert({ name: airfieldKey(name), code: code.trim().toUpperCase(), updated_at: new Date().toISOString() });
  return error;
}

// ---------- ช่องที่พิมพ์แก้เอง ----------
export async function loadEntries(y, m) {
  const { first, last } = monthRange(y, m);
  const { data, error } = await supabase.from("queue_entries")
    .select("crew_member_id,entry_date,code,kind,ac_type")
    .gte("entry_date", first).lte("entry_date", last);
  if (error) console.error(error);
  return data || [];
}

export async function saveEntry(crewId, date, { code, kind, ac_type }) {
  const { data: { session } } = await supabase.auth.getSession();
  const { error } = await supabase.from("queue_entries").upsert({
    crew_member_id: crewId, entry_date: date,
    code: (code || "").trim().toUpperCase() || null,
    kind, ac_type: ac_type || null,
    updated_by: session?.user?.id, updated_at: new Date().toISOString(),
  }, { onConflict: "crew_member_id,entry_date" });
  return error;
}

export async function deleteEntry(crewId, date) {
  const { error } = await supabase.from("queue_entries")
    .delete().eq("crew_member_id", crewId).eq("entry_date", date);
  return error;
}
