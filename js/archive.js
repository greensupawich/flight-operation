// =====================================================================
//  archive.js — export ข้อมูลจัดบินรายเดือน · เคลียร์ข้อมูลดิบ · อ่านไฟล์ย้อนหลัง (migration_25)
//   • ไฟล์หลัก  : flight-ops-YYYY-MM.zip  = data.json + media/<path> (รูป/วีดีโอ)
//   • ไฟล์อ่าน  : flight-ops-YYYY-MM.xlsx (เปิดใน Excel · import กลับใช้ .zip/.json)
//   • เคลียร์    : ต้อง export ก่อน + เก่ากว่า 3 เดือนเต็ม (ตรวจซ้ำในฐานข้อมูล)
//  ต้องโหลด JSZip / SheetJS (global JSZip, XLSX) ในหน้า archive.html
// =====================================================================
import { supabase } from "./supabase.js";
import { BUCKET, removeFiles } from "./media.js";

export const FORMAT = "flight-operation-archive";
const PILOT_POS = ["AC", "IP", "P", "CP", "N"];
const HOUR_POS = ["IP", "P", "CP"];

const pad = (n) => String(n).padStart(2, "0");
export function monthRange(ym /* 'YYYY-MM' */) {
  const [y, m] = ym.split("-").map(Number);
  return { first: `${ym}-01`, last: `${ym}-${pad(new Date(y, m, 0).getDate())}`, next: m === 12 ? `${y + 1}-01-01` : `${y}-${pad(m + 1)}-01` };
}
// เดือนล่าสุดที่เคลียร์ได้ (ตรงกับ archive_purge_month: เก็บ 3 เดือนเต็ม + เดือนปัจจุบัน)
export function purgeLimitYm(today = new Date()) {
  const d = new Date(today.getFullYear(), today.getMonth() - 4, 1);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

// ดึงทุกแถว (เกิน 1000 แถวก็ได้)
async function all(q) {
  const out = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await q().range(from, from + 999);
    if (error) throw error;
    out.push(...(data || []));
    if (!data || data.length < 1000) return out;
  }
}

// ---------- รายการเดือนที่มีข้อมูล + สถานะ export/เคลียร์ ----------
export async function listMonths() {
  const [dates, logRes] = await Promise.all([
    all(() => supabase.from("missions").select("mission_date").order("mission_date")),
    supabase.from("archive_log").select("*"),
  ]);
  const map = new Map();
  const get = (ym) => map.get(ym) || map.set(ym, { ym, missions: 0, log: null }).get(ym);
  dates.forEach((r) => { get(String(r.mission_date).slice(0, 7)).missions++; });
  if (logRes.error) console.warn("archive_log:", logRes.error.message);
  (logRes.data || []).forEach((l) => { get(String(l.ym).slice(0, 7)).log = l; });
  return { months: [...map.values()].sort((a, b) => b.ym.localeCompare(a.ym)), needsMigration: !!logRes.error };
}

// ---------- รวบรวมข้อมูล 1 เดือน ----------
export async function fetchMonth(ym, profile) {
  const { first, last } = monthRange(ym);
  const missions = await all(() => supabase.from("missions")
    .select("*, aircraft(id,tail_number,type), mission_crew(*), flight_legs(*), post_flight_reports(*), safety_reports(*)")
    .gte("mission_date", first).lte("mission_date", last).order("mission_date").order("takeoff_time"));
  const ids = missions.map((m) => m.id);

  const byDate = await all(() => supabase.from("discrepancies").select("*, aircraft(tail_number,type)")
    .gte("reported_date", first).lte("reported_date", last));
  const byMission = [];
  for (let i = 0; i < ids.length; i += 100) {
    const { data, error } = await supabase.from("discrepancies").select("*, aircraft(tail_number,type)").in("mission_id", ids.slice(i, i + 100));
    if (error) throw error;
    byMission.push(...(data || []));
  }
  const discrepancies = [...new Map([...byDate, ...byMission].map((d) => [d.id, d])).values()]
    .sort((a, b) => String(a.reported_date).localeCompare(String(b.reported_date)));

  const media = [];
  for (let i = 0; i < ids.length; i += 100) {
    const { data, error } = await supabase.from("report_media").select("*").in("mission_id", ids.slice(i, i + 100));
    if (error) { console.warn("report_media:", error.message); break; }
    media.push(...(data || []));
  }

  const opt = async (q) => { try { return await all(q); } catch (e) { console.warn(e.message); return []; } };
  const [day_notes, queue_entries, crew_unavailable, aircraft_status_history, crew_members, aircraft] = await Promise.all([
    opt(() => supabase.from("day_notes").select("*").gte("log_date", first).lte("log_date", last)),
    opt(() => supabase.from("queue_entries").select("*").gte("entry_date", first).lte("entry_date", last)),
    opt(() => supabase.from("crew_unavailable").select("*").gte("off_date", first).lte("off_date", last)),
    opt(() => supabase.from("aircraft_status_history").select("*").gte("log_date", first).lte("log_date", last)),
    opt(() => supabase.from("crew_members").select("*")),
    opt(() => supabase.from("aircraft").select("*")),
  ]);

  const data = {
    format: FORMAT, version: 1, month: ym,
    exported_at: new Date().toISOString(),
    exported_by: profile ? (profile.full_name || profile.email) : null,
    missions, discrepancies,
    media: media.map((x) => ({ ...x, file: `media/${x.storage_path}` })),
    day_notes, queue_entries, crew_unavailable, aircraft_status_history, crew_members, aircraft,
  };
  data.summary = summarize(data);
  return data;
}

// ---------- สรุป (ใช้ทั้งตอน export และตอนเปิดไฟล์ดู) ----------
const one = (x) => Array.isArray(x) ? x[0] : x;
export const reportOf = (m) => one(m.post_flight_reports);

export function summarize(data) {
  const crewById = new Map((data.crew_members || []).map((c) => [c.id, c]));
  const perAc = new Map(), perCrew = new Map();
  let hours = 0, flights = 0;
  for (const m of data.missions || []) {
    const r = reportOf(m);
    if (!r) continue;
    const h = Number(r.total_hours || 0);
    hours += h; flights++;
    const tail = m.aircraft?.tail_number || "-";
    const a = perAc.get(tail) || perAc.set(tail, { tail, type: m.aircraft?.type || "", flights: 0, hours: 0, discrepancies: 0 }).get(tail);
    a.flights++; a.hours += h;
    if (m.status === "cancelled") continue;
    // เหมือน crew.js: เที่ยว = ตำแหน่งนักบินทุกตำแหน่ง · ชม. = IP/P/CP · คนเดียวหลายตำแหน่ง = 1 เที่ยว
    const pos = new Map();
    for (const c of m.mission_crew || []) {
      const p = String(c.position || "").trim().toUpperCase();
      if (!c.crew_member_id || !PILOT_POS.includes(p)) continue;
      (pos.get(c.crew_member_id) || pos.set(c.crew_member_id, new Set()).get(c.crew_member_id)).add(p);
    }
    pos.forEach((set, id) => {
      const cm = crewById.get(id);
      const s = perCrew.get(id) || perCrew.set(id, { id, code: cm?.code || "", name: cm?.full_name || "", rank: cm?.rank || "", flights: 0, hours: 0 }).get(id);
      s.flights++;
      if ([...set].some((p) => HOUR_POS.includes(p))) s.hours += h;
    });
  }
  for (const d of data.discrepancies || []) {
    const tail = d.aircraft?.tail_number || "-";
    const a = perAc.get(tail) || perAc.set(tail, { tail, type: d.aircraft?.type || "", flights: 0, hours: 0, discrepancies: 0 }).get(tail);
    a.discrepancies++;
  }
  const r1 = (n) => Math.round(n * 10) / 10;
  return {
    missions: (data.missions || []).length, flights, hours: r1(hours),
    discrepancies: (data.discrepancies || []).length,
    safety_reports: (data.missions || []).reduce((t, m) => t + (m.safety_reports || []).length, 0),
    media: (data.media || []).length,
    per_aircraft: [...perAc.values()].map((a) => ({ ...a, hours: r1(a.hours) })).sort((a, b) => a.tail.localeCompare(b.tail)),
    per_crew: [...perCrew.values()].map((c) => ({ ...c, hours: r1(c.hours) })).sort((a, b) => b.hours - a.hours || b.flights - a.flights),
  };
}

// ---------- สร้างไฟล์ ----------
export async function buildZip(data, onProgress) {
  const zip = new JSZip();
  zip.file("data.json", JSON.stringify(data, null, 1));
  const failed = [];
  for (let i = 0; i < data.media.length; i++) {
    const m = data.media[i];
    onProgress?.(`ดาวน์โหลดไฟล์แนบ ${i + 1}/${data.media.length}`);
    const { data: blob, error } = await supabase.storage.from(BUCKET).download(m.storage_path);
    if (error || !blob) { failed.push(m.file_name || m.storage_path); continue; }
    zip.file(m.file, blob);
  }
  onProgress?.("กำลังบีบอัดไฟล์…");
  const blob = await zip.generateAsync({ type: "blob", compression: "DEFLATE", compressionOptions: { level: 6 } },
    (meta) => onProgress?.(`กำลังบีบอัด ${Math.round(meta.percent)}%`));
  return { blob, failed };
}

export function buildXlsx(data, kindLabel = (k) => k) {
  const wb = XLSX.utils.book_new();
  const add = (name, rows) => XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(rows.length ? rows : [{ "": "— ไม่มีข้อมูล —" }]), name);
  const ac = (a) => a ? `${a.type || ""}/${a.tail_number || ""}` : "";
  const mById = new Map(data.missions.map((m) => [m.id, m]));
  const mediaCount = (key, id) => data.media.filter((x) => x[key] === id).length;

  add("ภารกิจ", data.missions.map((m) => {
    const r = reportOf(m) || {};
    return {
      "วันที่": m.mission_date, "Callsign": m.callsign || "", "ภารกิจ": m.mission_name || "", "ประเภท": kindLabel(m.kind),
      "เครื่อง": ac(m.aircraft), "เส้นทาง": m.route || "", "BRIEF": m.brief_time || "", "T/O": m.takeoff_time || "",
      "สถานะ": m.status || "", "ผลภารกิจ": r.result || "", "ชม.บิน": r.total_hours != null ? Number(r.total_hours) : "",
      "จุดจอดกลับ": r.parking_return || "", "หมายเหตุรายงาน": r.remarks || "",
      "ลูกเรือ": (m.mission_crew || []).slice().sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0))
        .map((c) => `${c.position || ""}: ${c.crew_name || ""}`).join(", "),
    };
  }));
  add("ลูกเรือ", data.missions.flatMap((m) => (m.mission_crew || []).slice().sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0))
    .map((c) => ({ "วันที่": m.mission_date, "Callsign": m.callsign || "", "ตำแหน่ง": c.position || "", "ชื่อ": c.crew_name || "",
                   "รหัสทะเบียน": data.crew_members.find((x) => x.id === c.crew_member_id)?.code || "" }))));
  add("ขาการบิน", data.missions.flatMap((m) => (m.flight_legs || []).slice().sort((a, b) => (a.leg_no || 0) - (b.leg_no || 0))
    .map((l) => ({ "วันที่": m.mission_date, "Callsign": m.callsign || "", "ขา": l.leg_no, "จาก": l.from_point || "", "ถึง": l.to_point || "", "ชม.": Number(l.hours || 0), "คณะวัง": l.vip ? "✓" : "" }))));
  add("ข้อขัดข้อง", data.discrepancies.map((d) => {
    const m = mById.get(d.mission_id);
    return { "วันที่": m?.mission_date || d.reported_date, "เครื่อง": ac(d.aircraft), "Callsign": m?.callsign || "",
             "รายละเอียด": d.description, "สถานะ": d.status || "", "ไฟล์แนบ": mediaCount("discrepancy_id", d.id) };
  }));
  add("รายงานอันตราย", data.missions.flatMap((m) => (m.safety_reports || []).map((s) => ({
    "วันที่": m.mission_date, "Callsign": m.callsign || "", "เครื่อง": ac(m.aircraft), "เส้นทาง": m.route || "",
    "เวลา": s.occurred_time || "", "ลักษณะเหตุการณ์": s.description, "ไฟล์แนบ": mediaCount("safety_report_id", s.id) }))));
  add("สรุปรายเครื่อง", data.summary.per_aircraft.map((a) => ({
    "เครื่อง": a.tail, "แบบ": a.type, "เที่ยวบิน": a.flights, "ชม.บิน": a.hours, "ข้อขัดข้อง": a.discrepancies })));
  add("สรุปรายนักบิน", data.summary.per_crew.map((c) => ({
    "รหัส": c.code, "ยศ": c.rank, "ชื่อ": c.name, "เที่ยวบิน": c.flights, "ชม.บิน (IP/P/CP)": c.hours })));
  const out = XLSX.write(wb, { bookType: "xlsx", type: "array" });
  return new Blob([out], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
}

export function downloadBlob(blob, name) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = name;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 60000);
}

export async function markExported(ym, counts) {
  const { error } = await supabase.rpc("archive_mark_exported", { p_ym: `${ym}-01`, p_counts: counts });
  return error;
}

// ---------- เคลียร์ 1 เดือน: ลบไฟล์แนบใน Storage ก่อน แล้วให้ฐานข้อมูลลบข้อมูลดิบ + เก็บยอดสรุป ----------
export async function purgeMonth(ym, onProgress) {
  const { first, last } = monthRange(ym);
  onProgress?.("กำลังลบไฟล์แนบ…");
  const { data: media, error: mErr } = await supabase.from("report_media")
    .select("storage_path, missions!inner(mission_date)")
    .gte("missions.mission_date", first).lte("missions.mission_date", last);
  if (mErr) return { error: mErr };
  if (media?.length) {
    const err = await removeFiles(media.map((x) => x.storage_path));
    if (err) return { error: err };
  }
  onProgress?.("กำลังเคลียร์ข้อมูลดิบ…");
  const { data, error } = await supabase.rpc("archive_purge_month", { p_ym: `${ym}-01` });
  return { data, error };
}

// ---------- เปิดไฟล์ย้อนหลัง (.zip หรือ .json) ----------
//  คืน { data, mediaUrl: Map(storage_path -> blob URL) }
export async function readArchiveFile(file) {
  const mediaUrl = new Map();
  let data;
  if (/\.json$/i.test(file.name) || file.type === "application/json") {
    data = JSON.parse(await file.text());
  } else {
    const zip = await JSZip.loadAsync(file);
    const j = zip.file("data.json");
    if (!j) throw new Error("ไม่พบ data.json ในไฟล์ zip");
    data = JSON.parse(await j.async("string"));
    for (const m of data.media || []) {
      const f = zip.file(m.file);
      if (!f) continue;
      const blob = new Blob([await f.async("arraybuffer")], { type: m.mime_type || "" });
      mediaUrl.set(m.storage_path, URL.createObjectURL(blob));
    }
  }
  if (data?.format !== FORMAT) throw new Error("ไฟล์นี้ไม่ใช่ไฟล์ export ของ Flight Operation");
  data.summary = summarize(data);
  return { data, mediaUrl };
}
