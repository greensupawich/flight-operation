// =====================================================================
//  ui.js — ส่วนประกอบหน้าจอที่ใช้ร่วมกัน (แถบเมนูด้านบน)
// =====================================================================
import { signOut, canPlan, isAdmin } from "./auth.js";

const LINKS = [
  { href: "home.html",      label: "หน้าหลัก" },
  { href: "dashboard.html", label: "ภารกิจ" },
  { href: "crew.html",      label: "ทะเบียนลูกเรือ" },
  { href: "stats.html",     label: "สถิติ" },
  { href: "admin.html",     label: "ผู้ดูแล", adminOnly: true },
];

// วาดแถบเมนู แล้วเสียบไว้บนสุดของ body
export function renderTopbar(profile) {
  const here = location.pathname.split("/").pop() || "dashboard.html";
  const links = LINKS
    .filter((l) => !l.adminOnly || isAdmin(profile))
    .map((l) => `<a href="${l.href}" class="${l.href === here ? "active" : ""}">${l.label}</a>`)
    .join("");

  const bar = document.createElement("div");
  bar.className = "topbar";
  bar.innerHTML = `
    <div class="wrap">
      <div class="brand"><span class="mk">🛩️</span> Flight Operation</div>
      <nav class="nav">${links}</nav>
      <div class="userchip">
        <span class="role">${profile.role}</span>
        <span>${profile.full_name || profile.email}</span>
        <button class="btn sm ghost" id="__signout">ออก</button>
      </div>
    </div>`;
  document.body.prepend(bar);
  document.getElementById("__signout").addEventListener("click", signOut);
}

export { canPlan, isAdmin };
