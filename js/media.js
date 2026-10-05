// =====================================================================
//  media.js — รูป / วีดีโอ แนบในข้อขัดข้อง และรายงานอันตราย (migration_24)
//   • ไฟล์เก็บใน Storage bucket 'report-media' (private) path = <mission_id>/<uuid>.<ext>
//   • รูปย่อในเบราว์เซอร์ก่อนอัปโหลด (ด้านยาว ≤ 1600px, JPEG 80%) · วีดีโอ ≤ 50 MB ไม่ย่อ
//   • แสดงผลผ่าน signed URL (หมดอายุ 1 ชม.) · กดรูปย่อเพื่อเปิดเต็มจอ
// =====================================================================
import { supabase } from "./supabase.js";

export const BUCKET = "report-media";
export const MAX_VIDEO = 50 * 1024 * 1024;
const MAX_SIDE = 1600;

const isImage = (t) => /^image\//.test(t || "");
const isVideo = (t) => /^video\//.test(t || "");
export const fmtSize = (b) => b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`;
const escAttr = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

// ---------- ย่อรูป (gif ไม่ย่อ เพราะจะเสียภาพเคลื่อนไหว) ----------
export async function compressImage(file) {
  if (!isImage(file.type) || file.type === "image/gif") return file;
  try {
    const bmp = await createImageBitmap(file, { imageOrientation: "from-image" });
    const scale = Math.min(1, MAX_SIDE / Math.max(bmp.width, bmp.height));
    const w = Math.round(bmp.width * scale), h = Math.round(bmp.height * scale);
    const cv = document.createElement("canvas");
    cv.width = w; cv.height = h;
    cv.getContext("2d").drawImage(bmp, 0, 0, w, h);
    bmp.close?.();
    const blob = await new Promise((res) => cv.toBlob(res, "image/jpeg", 0.8));
    if (!blob || blob.size >= file.size) return file;            // ย่อแล้วใหญ่กว่า → ใช้ต้นฉบับ
    const name = file.name.replace(/\.[^.]+$/, "") + ".jpg";
    return new File([blob], name, { type: "image/jpeg" });
  } catch (e) {
    console.warn("compressImage:", e);
    return file;                                                 // เบราว์เซอร์อ่านไม่ได้ (เช่น HEIC บน Chrome) → อัปโหลดต้นฉบับ
  }
}

// ตรวจไฟล์ก่อนอัปโหลด — คืนข้อความผิดพลาด หรือ null
export function checkFile(file) {
  if (!isImage(file.type) && !isVideo(file.type)) return `${file.name}: รองรับเฉพาะรูปและวีดีโอ`;
  if (isVideo(file.type) && file.size > MAX_VIDEO) return `${file.name}: วีดีโอใหญ่เกิน 50 MB (${fmtSize(file.size)})`;
  return null;
}

// ---------- อัปโหลด 1 ไฟล์ ----------
//  parent = { discrepancy_id } หรือ { safety_report_id }
export async function uploadMedia(missionId, parent, file) {
  const bad = checkFile(file);
  if (bad) return { error: { message: bad } };
  const f = await compressImage(file);
  if (f.size > MAX_VIDEO) return { error: { message: `${file.name}: ไฟล์ใหญ่เกิน 50 MB` } };
  const ext = (f.name.match(/\.([a-z0-9]+)$/i)?.[1] || (isVideo(f.type) ? "mp4" : "jpg")).toLowerCase();
  const path = `${missionId}/${crypto.randomUUID()}.${ext}`;

  const up = await supabase.storage.from(BUCKET).upload(path, f, { contentType: f.type, upsert: false });
  if (up.error) return { error: up.error };

  const { data, error } = await supabase.from("report_media").insert({
    mission_id: missionId, ...parent,
    storage_path: path, mime_type: f.type, file_name: file.name, size_bytes: f.size,
  }).select("*").single();
  if (error) { await supabase.storage.from(BUCKET).remove([path]); return { error }; }
  return { data };
}

// อัปโหลดหลายไฟล์ตามลำดับ · onProgress(i, n) · คืน [ข้อความผิดพลาด]
export async function uploadMany(missionId, parent, files, onProgress) {
  const errs = [];
  for (let i = 0; i < files.length; i++) {
    onProgress?.(i + 1, files.length);
    const { error } = await uploadMedia(missionId, parent, files[i]);
    if (error) errs.push(error.message);
  }
  return errs;
}

// ---------- โหลดรายการไฟล์ของภารกิจ + signed URL ----------
export async function loadMissionMedia(missionId) {
  const { data, error } = await supabase.from("report_media")
    .select("*").eq("mission_id", missionId).order("created_at");
  if (error) { console.warn("report_media:", error.message); return []; }
  return withUrls(data || []);
}

export async function withUrls(rows) {
  if (!rows.length) return rows;
  const { data } = await supabase.storage.from(BUCKET)
    .createSignedUrls(rows.map((r) => r.storage_path), 3600);
  const byPath = new Map((data || []).map((d) => [d.path, d.signedUrl]));
  return rows.map((r) => ({ ...r, url: byPath.get(r.storage_path) || "" }));
}

// ---------- ลบ ----------
export async function deleteMedia(row) {
  const rm = await supabase.storage.from(BUCKET).remove([row.storage_path]);
  if (rm.error) return rm.error;
  const { error } = await supabase.from("report_media").delete().eq("id", row.id);
  return error;
}

// ลบไฟล์ใน Storage ทีละชุด (ใช้ก่อนลบข้อขัดข้อง/รายงานอันตราย/เคลียร์เดือน)
export async function removeFiles(paths) {
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await supabase.storage.from(BUCKET).remove(paths.slice(i, i + 100));
    if (error) return error;
  }
  return null;
}

// ---------- แสดงผล ----------
//  items: [{ id?, url, mime_type, file_name, size_bytes }] · canDelete → มีปุ่ม ×
export function thumbsHtml(items, { canDelete = false } = {}) {
  if (!items.length) return "";
  return `<div class="media-grid">${items.map((m, i) => {
    const inner = isVideo(m.mime_type)
      ? `<video src="${escAttr(m.url)}#t=0.1" preload="metadata" muted playsinline></video><span class="play">▶</span>`
      : `<img src="${escAttr(m.url)}" alt="${escAttr(m.file_name)}" loading="lazy">`;
    return `<div class="mthumb" data-mi="${i}" title="${escAttr(m.file_name || "")}${m.size_bytes ? " · " + fmtSize(m.size_bytes) : ""}">
      <button type="button" class="mopen" data-mopen="${i}">${inner}</button>
      ${canDelete ? `<button type="button" class="mdel" data-mdel="${i}" title="ลบไฟล์นี้">×</button>` : ""}
    </div>`;
  }).join("")}</div>`;
}

// ผูกปุ่มเปิด/ลบในกล่องที่วาดด้วย thumbsHtml
export function bindThumbs(box, items, onDelete) {
  box.querySelectorAll("[data-mopen]").forEach((b) =>
    b.addEventListener("click", () => openLightbox(items, +b.dataset.mopen)));
  box.querySelectorAll("[data-mdel]").forEach((b) =>
    b.addEventListener("click", () => onDelete?.(items[+b.dataset.mdel])));
}

// เปิดดูเต็มจอ · ← → เลื่อน · Esc ปิด
export function openLightbox(items, start = 0) {
  let i = start;
  const lb = document.createElement("div");
  lb.className = "lightbox";
  lb.innerHTML = `<button class="lb-x" title="ปิด">×</button>
    <button class="lb-nav lb-prev" title="ก่อนหน้า">‹</button>
    <div class="lb-body"></div>
    <button class="lb-nav lb-next" title="ถัดไป">›</button>
    <div class="lb-cap"></div>`;
  const body = lb.querySelector(".lb-body"), cap = lb.querySelector(".lb-cap");
  const show = () => {
    const m = items[i];
    body.innerHTML = isVideo(m.mime_type)
      ? `<video src="${escAttr(m.url)}" controls autoplay playsinline></video>`
      : `<img src="${escAttr(m.url)}" alt="">`;
    cap.textContent = `${i + 1}/${items.length}${m.file_name ? " · " + m.file_name : ""}`;
    lb.querySelector(".lb-prev").hidden = lb.querySelector(".lb-next").hidden = items.length < 2;
  };
  const close = () => { lb.remove(); document.removeEventListener("keydown", onKey); };
  const step = (d) => { i = (i + d + items.length) % items.length; show(); };
  const onKey = (e) => {
    if (e.key === "Escape") close();
    else if (e.key === "ArrowLeft") step(-1);
    else if (e.key === "ArrowRight") step(1);
  };
  lb.addEventListener("click", (e) => { if (e.target === lb) close(); });
  lb.querySelector(".lb-x").addEventListener("click", close);
  lb.querySelector(".lb-prev").addEventListener("click", () => step(-1));
  lb.querySelector(".lb-next").addEventListener("click", () => step(1));
  document.addEventListener("keydown", onKey);
  document.body.appendChild(lb);
  show();
}

// เปิดหน้าต่างเลือกไฟล์ (รูป/วีดีโอ หลายไฟล์) — คืน [File]
export const ACCEPT = "image/*,video/*";
export function pickFiles() {
  return new Promise((resolve) => {
    const inp = document.createElement("input");
    inp.type = "file"; inp.accept = ACCEPT; inp.multiple = true;
    inp.addEventListener("change", () => resolve([...inp.files]));
    inp.addEventListener("cancel", () => resolve([]));
    inp.click();
  });
}
