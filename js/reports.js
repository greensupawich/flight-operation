// =====================================================================
//  reports.js — รายงานหลังบิน + ขาการบิน + ข้อขัดข้อง + รายงานอันตราย
//  บันทึกรายงาน → trigger ในฐานข้อมูลกระจาย ชม. ไปลูกเรือ/เครื่องเอง
// =====================================================================
import { supabase } from "./supabase.js";
import { removeFiles } from "./media.js";

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

// คืน { error, id } — id ใช้ผูกรูป/วีดีโอที่เลือกไว้ตอนเพิ่ม
export async function addDiscrepancy(missionId, aircraftId, description) {
  const { data: { session } } = await supabase.auth.getSession();
  const { data, error } = await supabase.from("discrepancies").insert({
    mission_id: missionId, aircraft_id: aircraftId, description, created_by: session?.user?.id,
  }).select("id").single();
  return { error, id: data?.id };
}

// ลบไฟล์แนบใน Storage ก่อน (แถว report_media หายตาม cascade)
export async function deleteDiscrepancy(id) {
  const { data: media } = await supabase.from("report_media").select("storage_path").eq("discrepancy_id", id);
  const { error } = await supabase.from("discrepancies").delete().eq("id", id);
  if (!error && media?.length) await removeFiles(media.map((m) => m.storage_path));
  return error;
}

// ---------- รายงานอันตราย (safety report) — ไม่บังคับ · มีได้หลายรายการ/ภารกิจ ----------
export async function loadSafety(missionId) {
  const { data, error } = await supabase.from("safety_reports")
    .select("*").eq("mission_id", missionId).order("created_at");
  if (error) { console.warn("safety_reports:", error.message); return []; }
  return data || [];
}

// บันทึกทั้งชุดแบบคง id เดิม (ไฟล์แนบผูกกับ id จึงห้ามลบ-สร้างใหม่)
//  items: [{ id?, occurred_time, description }] · รายการที่ไม่มีลักษณะเหตุการณ์จะไม่ถูกเก็บ
//  คืน { error, ids } — ids[i] = id ของ items[i] (null ถ้าไม่ได้เก็บ)
export async function saveSafety(missionId, items) {
  const { data: { session } } = await supabase.auth.getSession();
  const ids = (items || []).map(() => null);
  const keep = new Set((items || []).filter((it) => it.id && (it.description || "").trim()).map((it) => it.id));

  // 1) ลบรายการที่ถูกเอาออก (รวมไฟล์แนบใน Storage)
  const { data: old, error: oldErr } = await supabase.from("safety_reports").select("id").eq("mission_id", missionId);
  if (oldErr) return { error: oldErr, ids };
  const gone = (old || []).map((r) => r.id).filter((id) => !keep.has(id));
  if (gone.length) {
    const { data: media } = await supabase.from("report_media").select("storage_path").in("safety_report_id", gone);
    const { error } = await supabase.from("safety_reports").delete().in("id", gone);
    if (error) return { error, ids };
    if (media?.length) await removeFiles(media.map((m) => m.storage_path));
  }

  // 2) แก้ของเดิม / เพิ่มของใหม่
  for (let i = 0; i < (items || []).length; i++) {
    const it = items[i];
    const description = (it.description || "").trim();
    if (!description) continue;
    const row = { occurred_time: (it.occurred_time || "").trim() || null, description };
    if (it.id) {
      const { error } = await supabase.from("safety_reports").update(row).eq("id", it.id);
      if (error) return { error, ids };
      ids[i] = it.id;
    } else {
      const { data, error } = await supabase.from("safety_reports")
        .insert({ ...row, mission_id: missionId, created_by: session?.user?.id }).select("id").single();
      if (error) return { error, ids };
      ids[i] = data.id;
    }
  }
  return { error: null, ids };
}
