// =====================================================================
//  supabase.js — ตั้งค่าการเชื่อมต่อ Supabase
//  ⚠️ แก้ 2 ค่าด้านล่างให้เป็นของโปรเจกต์คุณ (Supabase → Project Settings → API)
//  anon key เปิดเผยได้ปลอดภัย เพราะ RLS คุมสิทธิ์อยู่ที่ฐานข้อมูล
//  ห้ามใส่ service_role key ในไฟล์นี้เด็ดขาด
// =====================================================================

const SUPABASE_URL = "https://iljapjszrjuzjjbtxctu.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlsamFwanN6cmp1empqYnR4Y3R1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxMTAwODksImV4cCI6MjEwNDY4NjA4OX0.2SLAx19gCIgIPooZp9TdAGa5ShbZNlcGtaIP4LV6ppg";

// โหลด SDK จาก CDN แบบ ESM แล้ว export client ให้ไฟล์อื่นใช้
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});

// URL ที่ให้ Google เด้งกลับหลังล็อกอิน (ต้องตรงกับที่ตั้งใน Supabase → Auth → URL config)
export const REDIRECT_URL = window.location.origin + window.location.pathname.replace(/[^/]+$/, "") + "home.html";
