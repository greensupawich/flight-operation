// =====================================================================
//  status.js — สถานภาพเครื่องบิน + ข้อขัดข้อง 3 ไฟลท์ล่าสุด
// =====================================================================
import { supabase } from "./supabase.js";

export const AC_STATUS = ["FMC", "PMC", "NMC"];
export const AC_STATUS_LABEL = {
  FMC: "FMC · พร้อมบิน",
  PMC: "PMC · พร้อมบางภารกิจ",
  NMC: "NMC · ไม่พร้อมบิน",
};
// สี (พื้น/ตัวอักษร) ของแต่ละสถานภาพ
export const AC_STATUS_COLORS = {
  FMC: { bg: "#2E7D5B", fg: "#ffffff" },   // เขียว
  PMC: { bg: "#E0A32B", fg: "#2a1e00" },   // เหลือง
  NMC: { bg: "#C0392B", fg: "#ffffff" },   // แดง
};

export async function loadAircraft() {
  const { data, error } = await supabase
    .from("aircraft")
    .select("id,tail_number,type,status,status_note,status_updated_at,total_hours")
    .order("tail_number");
  if (error) { console.error(error); return []; }
  return data || [];
}

export async function setAircraftStatus(id, status, note) {
  const { error } = await supabase.from("aircraft")
    .update({ status, status_note: (note || "").trim() || null }).eq("id", id);
  return error;
}

// ข้อขัดข้องของทุกเครื่อง จัดกลุ่มเป็น "ไฟลท์" (ตามภารกิจ · ถ้าไม่มีภารกิจใช้วันที่)
// คืน Map(aircraftId -> [{ date, callsign, items:[{description,status}] }]) เรียงใหม่→เก่า
export async function loadRecentDiscrepancies() {
  const { data, error } = await supabase
    .from("discrepancies")
    .select("aircraft_id,description,status,reported_date,mission_id,missions(mission_date,callsign)")
    .order("reported_date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) { console.error(error); return new Map(); }

  const byAc = new Map();
  (data || []).forEach((d) => {
    if (!d.aircraft_id) return;
    const date = d.missions?.mission_date || d.reported_date;
    const callsign = d.missions?.callsign || "";
    const flightKey = d.mission_id || `date:${date}`;
    if (!byAc.has(d.aircraft_id)) byAc.set(d.aircraft_id, new Map());
    const flights = byAc.get(d.aircraft_id);
    if (!flights.has(flightKey)) flights.set(flightKey, { date, callsign, items: [] });
    flights.get(flightKey).items.push({ description: d.description, status: d.status });
  });

  const out = new Map();
  byAc.forEach((flights, acId) => {
    const list = [...flights.values()].sort((a, b) => String(b.date).localeCompare(String(a.date)));
    out.set(acId, list.slice(0, 1));   // เอาแค่ไฟลท์ล่าสุด
  });
  return out;
}

// สถานภาพของทุกเครื่อง ณ วันที่กำหนด (จากประวัติ migration_18)
// คืน Map(aircraftId -> { status, note, log_date }) · ถ้ายังไม่มีตารางประวัติ คืน null
export async function loadStatusOn(dateStr) {
  const { data, error } = await supabase.rpc("aircraft_status_on", { p_date: dateStr });
  if (error) return null;
  const map = new Map();
  (data || []).forEach((r) => map.set(r.aircraft_id, { status: r.status, note: r.note, log_date: r.log_date }));
  return map;
}

// ---------- ข้อขัดข้องประจำเครื่อง (รายการค้างของเครื่อง) ----------
export async function loadDefects() {
  const { data, error } = await supabase.from("aircraft_defects")
    .select("aircraft_id,seq,description").order("aircraft_id").order("seq");
  const map = new Map();
  if (!error) (data || []).forEach(d => {
    if (!map.has(d.aircraft_id)) map.set(d.aircraft_id, []);
    map.get(d.aircraft_id).push(d.description);
  });
  return map;
}
export async function saveDefects(aircraftId, descriptions) {
  await supabase.from("aircraft_defects").delete().eq("aircraft_id", aircraftId);
  const rows = (descriptions || []).map((t,i) => ({ aircraft_id: aircraftId, seq: i+1, description: t }))
    .filter(r => r.description);
  if (!rows.length) return null;
  const { error } = await supabase.from("aircraft_defects").insert(rows);
  return error;
}

// ---------- รายการเช็คตามวงรอบ ----------
export async function loadChecks() {
  const { data, error } = await supabase.from("aircraft_checks")
    .select("aircraft_id,seq,name,due_text").order("aircraft_id").order("seq");
  const map = new Map();
  if (!error) (data || []).forEach(c => {
    if (!map.has(c.aircraft_id)) map.set(c.aircraft_id, []);
    map.get(c.aircraft_id).push({ name: c.name, due_text: c.due_text || "" });
  });
  return map;
}
export async function saveChecks(aircraftId, list) {
  await supabase.from("aircraft_checks").delete().eq("aircraft_id", aircraftId);
  const rows = (list || []).map((c,i) => ({ aircraft_id: aircraftId, seq: i+1, name: (c.name||"").trim(), due_text: (c.due_text||"").trim() || null }))
    .filter(r => r.name);
  if (!rows.length) return null;
  const { error } = await supabase.from("aircraft_checks").insert(rows);
  return error;
}
