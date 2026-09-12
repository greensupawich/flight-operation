// =====================================================================
//  combobox.js — ช่องพิมพ์ได้ + dropdown ที่ "ผูกกับรายการจริง" เท่านั้น
//  ต่างจาก <input list=datalist> ตรงที่บอกสถานะชัดว่าผูกสำเร็จหรือยัง
//  items = [{ id, label, hint }]
// =====================================================================
export function attachCombo(root, items, { value = "", id = null, onChange, emptyHtml = "" } = {}) {
  const input = root.querySelector(".cb-input");
  const list  = root.querySelector(".cb-list");
  const badge = root.querySelector(".cb-badge");
  input.value = value;

  const byLabel = new Map(), byHint = new Map();
  items.forEach((it) => {
    byLabel.set(it.label.trim().toLowerCase(), it);
    if (it.hint) byHint.set(String(it.hint).trim().toLowerCase(), it);
  });
  // พิมพ์ได้ทั้งชื่อและรหัส
  const resolve = (t) => {
    const k = (t || "").trim().toLowerCase();
    return byLabel.get(k) || byHint.get(k) || null;
  };

  function mark(item) {
    const typed = !!input.value.trim();
    input.classList.toggle("linked", !!item);
    input.classList.toggle("unlinked", !item && typed);
    badge.textContent = item ? "✓" : (typed ? "!" : "");
    badge.title = item ? `ผูกแล้ว: ${item.hint || item.label}` : (typed ? "ยังไม่ได้เลือกจากรายการ" : "");
    onChange && onChange({ text: input.value, item });
  }

  function draw() {
    const k = input.value.trim().toLowerCase();
    const hits = items.filter((it) => !k
      || it.label.toLowerCase().includes(k)
      || String(it.hint || "").toLowerCase().includes(k)).slice(0, 60);
    list.innerHTML = hits.length
      ? hits.map((it) => `<div class="cb-opt" data-id="${it.id}"><b>${esc(it.label)}</b><span>${esc(it.hint || "")}</span></div>`).join("")
      : `<div class="cb-empty">${emptyHtml || "ไม่พบในรายการ"}</div>`;
    list.hidden = false;
    list.querySelectorAll(".cb-opt").forEach((o) =>
      o.addEventListener("mousedown", (e) => {      // mousedown ทำงานก่อน blur
        e.preventDefault();
        const it = items.find((x) => String(x.id) === o.dataset.id);
        input.value = it.label; mark(it); list.hidden = true;
      }));
  }

  input.addEventListener("focus", draw);
  input.addEventListener("input", () => { mark(resolve(input.value)); draw(); });
  input.addEventListener("blur", () => setTimeout(() => { list.hidden = true; }, 120));
  input.addEventListener("keydown", (e) => {
    const opts = [...list.querySelectorAll(".cb-opt")];
    if (e.key === "Escape") { list.hidden = true; return; }
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (list.hidden) draw();
      const cur = opts.findIndex((o) => o.classList.contains("on"));
      const nx = e.key === "ArrowDown" ? Math.min(cur + 1, opts.length - 1) : Math.max(cur - 1, 0);
      opts.forEach((o) => o.classList.remove("on"));
      if (opts[nx]) { opts[nx].classList.add("on"); opts[nx].scrollIntoView({ block: "nearest" }); }
    }
    if (e.key === "Enter" && !list.hidden) {
      const on = list.querySelector(".cb-opt.on") || opts[0];
      if (on) { e.preventDefault();
        const it = items.find((x) => String(x.id) === on.dataset.id);
        input.value = it.label; mark(it); list.hidden = true; }
    }
  });

  mark(id ? items.find((x) => String(x.id) === String(id)) : resolve(value));
  return { resolve };
}

export const comboHTML = (placeholder = "") =>
  `<div class="cb"><input class="cb-input" autocomplete="off" placeholder="${placeholder}">
     <span class="cb-badge"></span><div class="cb-list" hidden></div></div>`;

function esc(s){return String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));}
