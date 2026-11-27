import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const GOOGLE_OAUTH_CLIENT_ID = Deno.env.get("GOOGLE_OAUTH_CLIENT_ID") ?? "";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders });
}
function fail(message: string, status = 400) { return json({ ok: false, error: message }, status); }
function isObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function verifyGoogleAccessToken(request: Request) {
  const header = request.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw Object.assign(new Error("Login Google diperlukan."), { status: 401 });
  const token = match[1].trim();
  if (token.length < 30 || token.length > 8192) throw Object.assign(new Error("Token Google tidak valid."), { status: 401 });

  const response = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw Object.assign(new Error("Sesi Google tidak valid atau sudah kedaluwarsa. Silakan login ulang."), { status: 401 });
  const user = await response.json();
  if (!user.sub || !user.email || user.email_verified !== true) {
    throw Object.assign(new Error("Email Google harus sudah terverifikasi."), { status: 403 });
  }

  // Optional extra audience pinning. Set GOOGLE_OAUTH_CLIENT_ID in the function
  // environment to the Android OAuth client ID registered for this app.
  if (GOOGLE_OAUTH_CLIENT_ID) {
    const infoUrl = new URL("https://oauth2.googleapis.com/tokeninfo");
    infoUrl.searchParams.set("access_token", token);
    const infoResponse = await fetch(infoUrl);
    if (!infoResponse.ok) throw Object.assign(new Error("Tidak dapat memverifikasi aplikasi Google."), { status: 401 });
    const info = await infoResponse.json();
    const issuedTo = String(info.issued_to ?? info.aud ?? "");
    if (issuedTo && issuedTo !== GOOGLE_OAUTH_CLIENT_ID) {
      throw Object.assign(new Error("Token Google bukan untuk aplikasi Kingdom In Chaos DTP."), { status: 401 });
    }
  }

  return {
    sub: String(user.sub),
    email: String(user.email).trim().toLowerCase(),
    email_verified: true,
    name: String(user.name ?? user.given_name ?? "Pemain Google").slice(0, 120),
    picture: String(user.picture ?? "").slice(0, 2048),
  };
}

async function requireData<T = unknown>(query: PromiseLike<{ data: T | null; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await query;
  if (error) throw Object.assign(new Error(error.message), { status: 500 });
  return data as T;
}

async function bootstrap(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>) {
  const profile = await requireData<any>(service.from("game_google_players").upsert({
    google_sub: identity.sub,
    email: identity.email,
    email_verified: true,
    google_name: identity.name,
    avatar_url: identity.picture,
    updated_at: new Date().toISOString(),
  }, { onConflict: "google_sub" }).select("*").single());
  const economy = await requireData<any>(service.from("game_google_player_economy").upsert({
    player_uuid: profile.player_uuid,
  }, { onConflict: "player_uuid", ignoreDuplicates: true }).select("*").maybeSingle());
  const wallet = economy || await requireData<any>(service.from("game_google_player_economy").select("*").eq("player_uuid", profile.player_uuid).single());
  return { profile, economy: wallet };
}

async function completeProfile(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>, body: Record<string, unknown>) {
  const nickname = typeof body.nickname === "string" ? body.nickname.trim() : "";
  if (nickname.length < 3 || nickname.length > 32) throw new Error("Nickname harus terdiri dari 3–32 karakter.");
  if (!/^[\p{L}\p{N} _.-]+$/u.test(nickname)) throw new Error("Nickname hanya boleh memakai huruf, angka, spasi, titik, garis bawah, atau tanda hubung.");

  const current = await requireData<any>(service.from("game_google_players").select("*").eq("google_sub", identity.sub).single());
  if (current.profile_completed) throw new Error("Profil akun ini sudah pernah diselesaikan.");
  const profile = await requireData<any>(service.from("game_google_players").update({
    nickname,
    profile_completed: true,
    updated_at: new Date().toISOString(),
  }).eq("player_uuid", current.player_uuid).eq("profile_completed", false).select("*").single());
  const economy = await requireData<any>(service.from("game_google_player_economy").select("*").eq("player_uuid", current.player_uuid).single());
  return { profile, economy };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return fail("Method not allowed", 405);
  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("Konfigurasi server database belum lengkap.");
    const identity = await verifyGoogleAccessToken(request);
    const body = await request.json().catch(() => ({}));
    if (!isObject(body)) return fail("Request body tidak valid.");
    const action = String(body.action ?? "");
    let data: unknown;

    if (action === "bootstrap") {
      data = await bootstrap(identity);
    } else if (action === "complete_profile") {
      data = await completeProfile(identity, body);
    } else if (action === "get_state") {
      data = await requireData<any>(service.rpc("game_google_player_state", { p_google_sub: identity.sub }));
    } else if (action === "buy_meat") {
      const amount = Number(body.amount);
      if (!Number.isInteger(amount) || amount < 1 || amount > 24) throw new Error("Jumlah daging harus 1–24.");
      data = await requireData<any>(service.rpc("game_google_buy_meat", { p_google_sub: identity.sub, p_amount: amount }));
    } else if (action === "consume_meat") {
      data = await requireData<any>(service.rpc("game_google_consume_meat", { p_google_sub: identity.sub }));
    } else if (action === "redeem_code") {
      const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
      if (!/^[A-Z0-9-]{4,40}$/.test(code)) throw new Error("Format kode hadiah tidak valid.");
      data = await requireData<any>(service.rpc("game_google_redeem_reward_code", { p_google_sub: identity.sub, p_code: code }));
    } else {
      return fail("Aksi pemain tidak dikenal.", 404);
    }
    return json({ ok: true, data });
  } catch (error) {
    const e = error as Error & { status?: number };
    console.error("google-player action failed:", e.message);
    return fail(e.message || "Permintaan pemain gagal.", e.status ?? 400);
  }
});
