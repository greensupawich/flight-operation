// =====================================================================
//  missions.js — โหลด/แสดงภารกิจ + สร้างภารกิจใหม่
// =====================================================================
import { supabase } from "./supabase.js";

const STATUS_LABEL = { planned:"วางแผน", flying:"กำลังบิน", completed:"เสร็จสิ้น", cancelled:"ยกเลิก" };

// ---------- โหลดภารกิจของวันที่กำหนด (พร้อมเครื่องและจำนวนลูกเรือ) ----------
export async function loadMissions(dateStr) {
  const { data, error } = await supabase
    .from("missions")
    .select("*, aircraft(tail_number,type), mission_crew(count)")
    .eq("mission_date", dateStr)
    .order("planned_time", { ascending: true });
  if (error) { console.error(error); return []; }
  return data || [];
}

// ---------- วาดการ์ดภารกิจ ----------
export function renderMissions(container, missions) {
  if (!missions.length) {
    container.innerHTML = `<div class="empty">ยังไม่มีภารกิจในวันนี้</div>`;
    return;
  }
  container.innerHTML = missions.map((m) => {
    const ac = m.aircraft ? `${m.aircraft.tail_number} · ${m.aircraft.type || "-"}` : "ยังไม่กำหนด";
    const crew = m.mission_crew?.[0]?.count ?? 0;
    return `
      <div class="mission">
        <div style="display:flex;justify-content:space-between;align-items:start;gap:10px">
          <h3>${esc(m.mission_name)}</h3>
          <span class="pill ${m.status}">${STATUS_LABEL[m.status] || m.status}</span>
        </div>
        <div class="row"><span>⏱️ <b>${esc(m.planned_time || "-")}</b></span><span>✈️ <b>${esc(ac)}</b></span></div>
        <div class="row"><span>🧭 เส้นทาง: <b>${esc(m.route || "-")}</b></span></div>
        <div class="row"><span>👥 ลูกเรือ: <b>${crew}</b> คน</span></div>
        <div style="margin-top:10px;display:flex;gap:8px">
          <a class="btn sm" href="mission.html?id=${m.id}">รายละเอียด/จัดลูกเรือ</a>
          <a class="btn sm accent" href="report.html?mission=${m.id}">รายงานหลังบิน</a>
        </div>
      </div>`;
  }).join("");
}

// ---------- สร้างภารกิจใหม่ ----------
export async function createMission(payload) {
  const { data:{ session } } = await supabase.auth.getSession();
  const { data, error } = await supabase
    .from("missions")
    .insert({ ...payload, created_by: session?.user?.id })
    .select()
    .single();
  if (error) { alert("บันทึกไม่สำเร็จ: " + error.message); return null; }
  return data;
}

// ---------- โหลดรายการเครื่องไว้ใช้ใน dropdown ----------
export async function loadAircraft() {
  const { data } = await supabase.from("aircraft").select("id,tail_number,type").order("tail_number");
  return data || [];
}

function esc(s){return String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));}
