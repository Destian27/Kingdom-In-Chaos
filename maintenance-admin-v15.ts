import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ADMIN_NAME = Deno.env.get("MAINTENANCE_ADMIN_NAME") ?? "";
const ADMIN_PASSWORD = Deno.env.get("MAINTENANCE_ADMIN_PASSWORD") ?? "";
const ORIGINS = (Deno.env.get("ADMIN_ALLOWED_ORIGINS") ?? "")
  .split(",").map((s) => s.trim()).filter(Boolean);
const service = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })
  : null;

function cors(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const allowed = ORIGINS.length === 0 || ORIGINS.includes(origin);
  return {
    "Access-Control-Allow-Origin": ORIGINS.length === 0 ? "*" : (allowed ? origin : "null"),
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  };
}
function response(req: Request, status: number, body: unknown): Response {
  const headers = cors(req);
  if (headers["Access-Control-Allow-Origin"] === "null") {
    return new Response(JSON.stringify({ error: "Origin tidak diizinkan" }), { status: 403, headers });
  }
  return new Response(JSON.stringify(body), { status, headers });
}
function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const ah = new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(a)));
  const bh = new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(b)));
  return equalBytes(ah, bh);
}
async function authorized(input: Record<string, unknown>): Promise<boolean> {
  if (!ADMIN_NAME || !ADMIN_PASSWORD) return false;
  const name = typeof input.name === "string" ? input.name : "";
  const password = typeof input.password === "string" ? input.password : "";
  if (!name || !password || name.length > 200 || password.length > 1000) return false;
  return (await constantTimeEqual(name, ADMIN_NAME)) && (await constantTimeEqual(password, ADMIN_PASSWORD));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return response(req, 405, { error: "Metode tidak diizinkan" });
  if (!service) return response(req, 503, { error: "Konfigurasi backend belum lengkap" });

  try {
    const raw = await req.text();
    if (raw.length > 32768) return response(req, 413, { error: "Permintaan terlalu besar" });
    const input = JSON.parse(raw) as Record<string, unknown>;
    if (!(await authorized(input))) return response(req, 401, { error: "Nama admin atau password salah" });

    const action = typeof input.action === "string" ? input.action : "";
    if (action === "login" || action === "get") {
      const { data, error } = await service.from("app_maintenance").select("*").eq("id", 1).maybeSingle();
      if (error || !data) return response(req, 503, { error: "Konfigurasi maintenance tidak tersedia" });
      return response(req, 200, { data });
    }

    if (action === "save") {
      if (typeof input.is_active !== "boolean") return response(req, 400, { error: "Status maintenance tidak valid" });
      const title = typeof input.title === "string" ? input.title.trim() : "";
      const message = typeof input.message === "string" ? input.message.trim() : "";
      if (title.length < 1 || title.length > 100) return response(req, 400, { error: "Judul harus 1-100 karakter" });
      if (message.length > 2000) return response(req, 400, { error: "Pesan maksimal 2000 karakter" });
      let endAt: string | null = null;
      if (input.end_at !== null && input.end_at !== undefined && input.end_at !== "") {
        if (typeof input.end_at !== "string" || !Number.isFinite(Date.parse(input.end_at))) {
          return response(req, 400, { error: "Waktu selesai tidak valid" });
        }
        endAt = new Date(input.end_at).toISOString();
        if (input.is_active && Date.parse(endAt) <= Date.now()) {
          return response(req, 400, { error: "Waktu selesai maintenance harus di masa depan" });
        }
      }
      const { data, error } = await service.rpc("admin_update_app_maintenance", {
        p_is_active: input.is_active,
        p_title: title,
        p_message: message,
        p_end_at: endAt,
      });
      if (error || !data) {
        console.error("maintenance update failed", error?.message ?? "empty result");
        return response(req, 500, { error: "Perubahan maintenance gagal disimpan" });
      }
      return response(req, 200, { data });
    }
    return response(req, 400, { error: "Aksi tidak dikenal" });
  } catch (error) {
    console.error("maintenance admin request failed", error instanceof Error ? error.message : "unknown");
    return response(req, 400, { error: "Permintaan tidak valid" });
  }
});
