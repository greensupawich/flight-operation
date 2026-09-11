// =====================================================================
//  admin.js — คำขอใช้งาน + จัดการผู้ใช้ (เฉพาะ admin)
//  ทุกการเขียนถูกบังคับด้วย RLS ว่าต้องเป็น admin เท่านั้น
// =====================================================================
import { supabase } from "./supabase.js";

export const ROLES  = ["admin","planner","pilot","crew","viewer"];
export const ROLE_LABEL = {
  admin:"ผู้ดูแลระบบ", planner:"ผู้วางแผน", pilot:"นักบิน", crew:"เจ้าหน้าที่", viewer:"ผู้ชม",
};
const STATUS = ["pending","active","disabled"];

// ---------- โหลดผู้ใช้ทั้งหมด ----------
export async function loadProfiles() {
  const { data, error } = await supabase
    .from("profiles").select("*").order("created_at", { ascending: true });
  if (error) { console.error(error); return []; }
  return data || [];
}

// ---------- อนุมัติคำขอ: pending → active + กำหนดบทบาท ----------
export async function approve(id, role) {
  const { error } = await supabase.from("profiles")
    .update({ status: "active", role }).eq("id", id);
  return error;
}

// ---------- ปฏิเสธคำขอ ----------
export async function reject(id) {
  const { error } = await supabase.from("profiles")
    .update({ status: "disabled" }).eq("id", id);
  return error;
}

// ---------- แก้บทบาท/สถานะของผู้ใช้เดิม ----------
export async function updateUser(id, role, status) {
  const { error } = await supabase.from("profiles")
    .update({ role, status }).eq("id", id);
  return error;
}

// =====================================================================
//  วาดตาราง "คำขอใช้งาน" (status = pending)
// =====================================================================
export function renderRequests(card, tbody, countEl, profiles, onDone) {
  const rows = profiles.filter((p) => p.status === "pending");
  card.hidden = rows.length === 0;                      // ซ่อนการ์ดถ้าไม่มีคำขอ
  countEl.textContent = rows.length ? `(${rows.length})` : "";
  if (!rows.length) return;

  tbody.innerHTML = rows.map((p) => `
    <tr data-id="${p.id}">
      <td>
        <div style="font-weight:600">${esc(p.full_name || "— ยังไม่กรอกชื่อ —")}</div>
        <div class="muted mono" style="font-size:12px">${esc(p.email)}</div>
      </td>
      <td>${esc(p.rank || "-")}</td>
      <td class="muted" style="font-size:12.5px">${fmtTime(p.created_at)}</td>
      <td>
        <select data-role style="min-width:120px">
          ${ROLES.filter(r=>r!=="admin").map(r=>`<option value="${r}" ${r==="crew"?"selected":""}>${ROLE_LABEL[r]}</option>`).join("")}
        </select>
      </td>
      <td style="white-space:nowrap">
        <button class="btn sm primary" data-approve>✓ อนุมัติ</button>
        <button class="btn sm" data-reject style="color:var(--crit)">ปฏิเสธ</button>
      </td>
    </tr>`).join("");

  tbody.querySelectorAll("[data-approve]").forEach((b) =>
    b.addEventListener("click", async (e) => {
      const tr = e.target.closest("tr");
      b.disabled = true; b.textContent = "…";
      const err = await approve(tr.dataset.id, tr.querySelector("[data-role]").value);
      if (err) { alert("อนุมัติไม่สำเร็จ: " + err.message); b.disabled = false; b.textContent = "✓ อนุมัติ"; }
      else onDone();
    }));

  tbody.querySelectorAll("[data-reject]").forEach((b) =>
    b.addEventListener("click", async (e) => {
      const tr = e.target.closest("tr");
      if (!confirm("ปฏิเสธคำขอนี้?")) return;
      b.disabled = true;
      const err = await reject(tr.dataset.id);
      if (err) { alert("ไม่สำเร็จ: " + err.message); b.disabled = false; }
      else onDone();
    }));
}

// =====================================================================
//  วาดตาราง "ผู้ใช้ทั้งหมด"
// =====================================================================
export function renderUsers(tbody, profiles, onDone) {
  const rows = profiles.filter((p) => p.status !== "pending");
  tbody.innerHTML = rows.length ? rows.map((p) => `
    <tr data-id="${p.id}">
      <td>
        <div style="font-weight:600">${esc(p.full_name || "-")}</div>
        <div class="muted mono" style="font-size:12px">${esc(p.email)}</div>
      </td>
      <td>${esc(p.rank || "-")}</td>
      <td><select data-role>${ROLES.map(r=>`<option value="${r}" ${r===p.role?"selected":""}>${ROLE_LABEL[r]}</option>`).join("")}</select></td>
      <td><select data-status>${STATUS.map(s=>`<option value="${s}" ${s===p.status?"selected":""}>${s}</option>`).join("")}</select></td>
      <td><button class="btn sm" data-save>บันทึก</button></td>
    </tr>`).join("")
    : `<tr><td colspan="5" class="empty">ยังไม่มีผู้ใช้ที่อนุมัติแล้ว</td></tr>`;

  tbody.querySelectorAll("[data-save]").forEach((b) =>
    b.addEventListener("click", async (e) => {
      const tr = e.target.closest("tr");
      b.disabled = true; b.textContent = "…";
      const err = await updateUser(tr.dataset.id,
        tr.querySelector("[data-role]").value, tr.querySelector("[data-status]").value);
      b.disabled = false; b.textContent = err ? "บันทึก" : "✓";
      if (err) alert("ไม่สำเร็จ: " + err.message); else onDone && onDone();
    }));
}

function fmtTime(iso){
  if (!iso) return "-";
  try { return new Date(iso).toLocaleString("th-TH", { dateStyle:"short", timeStyle:"short" }); }
  catch { return iso; }
}
function esc(s){return String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));}
