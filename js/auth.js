// =====================================================================
//  auth.js — ล็อกอิน Google + ยามเฝ้าสิทธิ์ (session/role guard)
//  ใช้ร่วมทุกหน้า: import แล้วเรียก requireAuth() ตอนหน้าโหลด
// =====================================================================
import { supabase, REDIRECT_URL } from "./supabase.js";

// ---------- ล็อกอินด้วย Google ----------
export async function signInWithGoogle() {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: REDIRECT_URL },
  });
  if (error) alert("เข้าสู่ระบบไม่สำเร็จ: " + error.message);
}

export async function signOut() {
  await supabase.auth.signOut();
  window.location.href = "index.html";
}

// ---------- ดึง session + profile ปัจจุบัน ----------
export async function getCurrentProfile() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return null;
  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", session.user.id)
    .single();
  return profile || { id: session.user.id, email: session.user.email, status: "pending", role: "viewer" };
}

// ---------- ยามเฝ้าหน้า: เรียกที่ต้นทุกหน้า (ยกเว้น index) ----------
//  allowedRoles = อาร์เรย์บทบาทที่เข้าหน้านี้ได้ (ว่าง = ทุก active user)
export async function requireAuth(allowedRoles = []) {
  const profile = await getCurrentProfile();

  if (!profile || !profile.email) {           // ยังไม่ล็อกอิน
    window.location.href = "index.html";
    return null;
  }
  if (profile.status !== "active") {           // ล็อกอินแล้วแต่ยังไม่อนุมัติ
    if (!location.pathname.endsWith("pending.html")) {
      window.location.href = "pending.html";
    }
    return null;
  }
  if (allowedRoles.length && !allowedRoles.includes(profile.role)) {
    alert("คุณไม่มีสิทธิ์เข้าหน้านี้");
    window.location.href = "dashboard.html";
    return null;
  }
  return profile;
}

// ---------- helper บทบาท ----------
export const canPlan  = (p) => p && ["admin", "planner"].includes(p.role);
export const isAdmin  = (p) => p && p.role === "admin";
