// =====================================================================
//  local-auth.js — โหมด PROTOTYPE (เก็บข้อมูลใน localStorage)
//  ใช้ทดสอบ flow login/ลงทะเบียน/สิทธิ์ บน localhost ก่อนต่อ Supabase จริง
//  ไม่มีการเชื่อมต่อเซิร์ฟเวอร์ — ข้อมูลอยู่ในเบราว์เซอร์เครื่องนี้เท่านั้น
// =====================================================================

export const ADMIN_EMAIL = "green.supawich@gmail.com";
export const ROLES = ["admin", "planner", "pilot", "crew", "viewer"];
export const ROLE_LABEL = {
  admin: "ผู้ดูแลระบบ (admin)",
  planner: "ผู้วางแผน (planner)",
  pilot: "นักบิน (pilot)",
  crew: "เจ้าหน้าที่ (crew)",
  viewer: "ผู้ชม (viewer)",
};

const USERS_KEY = "fo_users";
const SESSION_KEY = "fo_session";

// ---------- โหลด/บันทึกรายชื่อผู้ใช้ ----------
export function loadUsers() {
  let users = [];
  try { users = JSON.parse(localStorage.getItem(USERS_KEY)) || []; } catch { users = []; }

  // seed: ผู้ดูแลระบบเริ่มต้น (ค่าเริ่มต้นของระบบ)
  if (!users.some((u) => u.email === ADMIN_EMAIL)) {
    users.unshift({
      email: ADMIN_EMAIL,
      name: "ผู้ดูแลระบบ",
      position: "Admin",
      role: "admin",
      created_at: new Date().toISOString(),
    });
    saveUsers(users);
  }
  return users;
}

function saveUsers(users) {
  try { localStorage.setItem(USERS_KEY, JSON.stringify(users)); } catch {}
}

// ---------- ลงทะเบียนผู้ใช้ใหม่ ----------
//  คืน { ok, error }  — อีเมล green.supawich@gmail.com ถูกบังคับเป็น admin เสมอ
export function register({ email, name, position, role }) {
  email = (email || "").trim().toLowerCase();
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return { ok: false, error: "อีเมลไม่ถูกต้อง" };
  if (!name || !name.trim()) return { ok: false, error: "กรุณากรอกชื่อ" };

  const users = loadUsers();
  if (users.some((u) => u.email === email)) return { ok: false, error: "อีเมลนี้ลงทะเบียนแล้ว" };

  const finalRole = email === ADMIN_EMAIL ? "admin" : (ROLES.includes(role) ? role : "viewer");
  users.push({ email, name: name.trim(), position: (position || "").trim(), role: finalRole, created_at: new Date().toISOString() });
  saveUsers(users);
  return { ok: true };
}

// ---------- เข้าสู่ระบบ / ออกจากระบบ ----------
export function signIn(email) {
  email = (email || "").trim().toLowerCase();
  const user = loadUsers().find((u) => u.email === email);
  if (!user) return { ok: false, error: "ไม่พบบัญชีนี้ กรุณาลงทะเบียนก่อน" };
  try { localStorage.setItem(SESSION_KEY, email); } catch {}
  return { ok: true, user };
}

export function signOut() {
  try { localStorage.removeItem(SESSION_KEY); } catch {}
  window.location.href = "index.html";
}

export function currentUser() {
  let email = null;
  try { email = localStorage.getItem(SESSION_KEY); } catch {}
  if (!email) return null;
  let user = loadUsers().find((u) => u.email === email) || null;
  // บังคับสิทธิ์ admin ให้อีเมลผู้ดูแลเสมอ (กันข้อมูลถูกแก้)
  if (user && user.email === ADMIN_EMAIL) user.role = "admin";
  return user;
}

// ---------- ยามเฝ้าหน้า: เรียกที่ต้นหน้าใน (redirect ไป login ถ้ายังไม่เข้าระบบ) ----------
export function requireLogin() {
  const user = currentUser();
  if (!user) { window.location.href = "index.html"; return null; }
  return user;
}
