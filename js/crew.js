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
//   • hours   = ชม.บิน: นับ AC / IP / P / CP (N ไม่นับ · AC นับเมื่อผูกทะเบียน)
//   คนเดียวหลายตำแหน่งในภารกิจเดียว นับเป็น 1 เที่ยว
//  คืน { crew_member_id: { hours, flights } }
// =====================================================================
const PILOT_POSITIONS = ["AC", "IP", "P", "CP", "N"];
const HOUR_POSITIONS  = ["AC", "IP", "P", "CP"];

export async function loadMonthlyStats(year, month /* 0-11 */) {
  const pad = (n) => String(n).padStart(2, "0");
  const first = `${year}-${pad(month + 1)}-01`;
  const last  = `${year}-${pad(month + 1)}-${pad(new Date(year, month + 1, 0).getDate())}`;

  const { data, error } = await supabase
    .from("mission_crew")
    .select("crew_member_id, position, mission_id, missions!inner(mission_date, status, post_flight_reports(total_hours))")
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
    if (r.missions?.status === "cancelled") return;          // ยกเลิก = ไม่นับเที่ยวบิน
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

  // เดือนที่เคลียร์ข้อมูลดิบแล้ว → บวกยอดสรุปที่เก็บไว้ (migration_25 · ข้อมูลดิบส่วนนั้นไม่มีแล้ว จึงไม่นับซ้ำ)
  const { data: arc, error: arcErr } = await supabase.from("stats_crew_monthly")
    .select("crew_member_id, flights, hours").eq("ym", first);
  if (arcErr) console.warn("stats_crew_monthly:", arcErr.message);
  (arc || []).forEach((x) => {
    const st = by[x.crew_member_id] || (by[x.crew_member_id] = { hours: 0, flights: 0 });
    st.flights += Number(x.flights || 0);
    st.hours += Number(x.hours || 0);
  });
  return by;
}

// บันทึกชื่อเดิมของนักบิน: ลบที่เอาออก + เพิ่มที่ใหม่ (ไม่แย่งชื่อเดิมของคนอื่น)
export async function setAliases(crewId, list, current) {
  const squash = (t) => String(t || "").replace(/\s+/g, "");
  const want = [...new Set(list.map(squash).filter(Boolean))];
  const have = (current || []).map(squash);
  const remove = have.filter((a) => !want.includes(a));
  const add = want.filter((a) => !have.includes(a));
  if (remove.length) {
    const { error } = await supabase.from("crew_aliases").delete().eq("crew_member_id", crewId).in("alias", remove);
    if (error) return error;
  }
  if (add.length) {
    const { error } = await supabase.from("crew_aliases").insert(add.map((alias) => ({ alias, crew_member_id: crewId })));
    if (error) return error.message.includes("duplicate")
      ? { message: "ชื่อเดิมนี้ผูกกับนักบินคนอื่นอยู่แล้ว" } : error;
  }
  return null;
}

// =====================================================================
//  วันบินล่าสุดแยกแบบเครื่อง 500 / 600 — คิดจาก "ภารกิจจัดบิน" (ไม่ต้องรอรายงานหลังบิน)
//   • นับภารกิจที่วันที่ ≤ วันนี้ · ไม่ถูกยกเลิก · ไม่ใช่ STBY · ตำแหน่งนักบิน (AC/IP/P/CP/N)
//   • แบบเครื่องจาก aircraft.type ("…500" / "…600")
//  คืน { crew_member_id: { "500": "YYYY-MM-DD", "600": "YYYY-MM-DD" } }
// =====================================================================
export async function loadLastFlown(todayISO) {
  const out = {};
  const PAGE = 1000;
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await supabase
      .from("mission_crew")
      .select("crew_member_id, position, missions!inner(mission_date, status, kind, aircraft(type))")
      .not("crew_member_id", "is", null)
      .lte("missions.mission_date", todayISO)
      .range(from, from + PAGE - 1);
    if (error) { console.error(error); break; }
    (data || []).forEach((r) => {
      const m = r.missions;
      if (!m || m.status === "cancelled" || m.kind === "stby") return;
      if (!PILOT_POSITIONS.includes(String(r.position || "").trim().toUpperCase())) return;
      const t = String(m.aircraft?.type || "");
      const tp = /500/.test(t) ? "500" : /600/.test(t) ? "600" : null;
      if (!tp) return;
      const d = String(m.mission_date).slice(0, 10);
      const rec = out[r.crew_member_id] || (out[r.crew_member_id] = {});
      if (!rec[tp] || d > rec[tp]) rec[tp] = d;
    });
    if (!data || data.length < PAGE) break;
  }
  return out;
}
