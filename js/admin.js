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
export const DEFAULT_ADMIN_EMAIL = "green.supawich@gmail.com";
export const MAX_ADMINS = 3;
const isDefaultAdmin = (p) => String(p.email || "").toLowerCase() === DEFAULT_ADMIN_EMAIL;
const adminCount = (profiles) => profiles.filter((p) => p.role === "admin").length;

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
          ${ROLES.map(r=>`<option value="${r}" ${r==="crew"?"selected":""}
             ${r==="admin" && adminCount(profiles)>=MAX_ADMINS ? "disabled" : ""}>${ROLE_LABEL[r]}${r==="admin" && adminCount(profiles)>=MAX_ADMINS ? " (ครบ 3 คน)" : ""}</option>`).join("")}
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
  const rows = profiles.filter((p) => p.status !== "pending")
    .sort((a, b) => (isDefaultAdmin(b) - isDefaultAdmin(a)) || ((b.role === "admin") - (a.role === "admin")));
  const full = adminCount(profiles) >= MAX_ADMINS;

  tbody.innerHTML = rows.length ? rows.map((p) => {
    const locked = isDefaultAdmin(p);
    const roleOpts = ROLES.map((r) => {
      const block = r === "admin" && full && p.role !== "admin";
      return `<option value="${r}" ${r === p.role ? "selected" : ""} ${block ? "disabled" : ""}>${ROLE_LABEL[r]}${block ? " (ครบ 3 คน)" : ""}</option>`;
    }).join("");
    return `
    <tr data-id="${p.id}">
      <td>
        <div style="font-weight:600">${esc(p.full_name || "-")}
          ${locked ? `<span class="lock-badge" title="ผู้ดูแลหลัก ถอดสิทธิ์ไม่ได้">🔒 ผู้ดูแลหลัก</span>` : ""}</div>
        <div class="muted mono" style="font-size:12px">${esc(p.email)}</div>
      </td>
      <td>${esc(p.rank || "-")}</td>
      <td><select data-role ${locked ? "disabled" : ""}>${roleOpts}</select></td>
      <td><select data-status ${locked ? "disabled" : ""}>${STATUS.map(s=>`<option value="${s}" ${s===p.status?"selected":""}>${s}</option>`).join("")}</select></td>
      <td>${locked ? `<span class="muted" style="font-size:12px">ล็อก</span>` : `<button class="btn sm" data-save>บันทึก</button>`}</td>
    </tr>`;
  }).join("")
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

// =====================================================================
//  เพิ่มผู้ใช้แบบ manual (อีเมลที่อนุญาตล่วงหน้า)
// =====================================================================
export async function loadInvites() {
  const { data, error } = await supabase
    .from("user_invites").select("*").order("created_at", { ascending: false });
  if (error) { console.error(error); return []; }
  return data || [];
}

export async function addInvite({ email, full_name, rank, role }) {
  const { data: { session } } = await supabase.auth.getSession();
  const { error } = await supabase.from("user_invites").upsert({
    email: (email || "").trim().toLowerCase(),
    full_name: (full_name || "").trim() || null,
    rank: (rank || "").trim() || null,
    role,
    invited_by: session?.user?.id,
  }, { onConflict: "email" });
  return error;
}

export async function deleteInvite(email) {
  const { error } = await supabase.from("user_invites").delete().eq("email", email);
  return error;
}

export function renderInvites(tbody, invites, profiles, onDone) {
  const byEmail = new Map(profiles.map((p) => [String(p.email || "").toLowerCase(), p]));
  tbody.innerHTML = invites.length ? invites.map((iv) => {
    const p = byEmail.get(iv.email);
    const state = !p
      ? `<span style="color:var(--warn);font-weight:600">รอเข้าสู่ระบบครั้งแรก</span>`
      : p.status === "active"
        ? `<span style="color:var(--good);font-weight:600">✓ ใช้งานแล้ว</span>`
        : `<span style="color:var(--muted);font-weight:600">มีบัญชีแล้ว · ${esc(p.status)}</span>`;
    return `
    <tr data-email="${esc(iv.email)}">
      <td>
        <div style="font-weight:600">${esc(iv.full_name || "-")}</div>
        <div class="muted mono" style="font-size:12px">${esc(iv.email)}</div>
      </td>
      <td>${esc(iv.rank || "-")}</td>
      <td>${esc(ROLE_LABEL[iv.role] || iv.role)}</td>
      <td style="font-size:12.5px">${state}</td>
      <td><button class="btn sm" data-del style="color:var(--crit)">ลบ</button></td>
    </tr>`;
  }).join("")
  : `<tr><td colspan="5" class="empty">ยังไม่มีอีเมลที่เพิ่มไว้</td></tr>`;

  tbody.querySelectorAll("[data-del]").forEach((b) =>
    b.addEventListener("click", async (e) => {
      const email = e.target.closest("tr").dataset.email;
      if (!confirm(`ลบ ${email} ออกจากรายชื่อที่อนุญาต?\n(ถ้าเจ้าของอีเมลเข้าใช้งานแล้ว บัญชียังอยู่ — ปิดสิทธิ์ได้ที่ตาราง "ผู้ใช้ในระบบ")`)) return;
      b.disabled = true;
      const err = await deleteInvite(email);
      if (err) { alert("ลบไม่สำเร็จ: " + err.message); b.disabled = false; }
      else onDone();
    }));
}
