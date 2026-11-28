// v1.0.9 (isi sama dengan v1.0.7 + aksi "ping" untuk cek server). v1.0.7: LOGIN GOOGLE DIHAPUS TOTAL. Pemain masuk dengan Nama Pengguna + Kata Sandi (hash PBKDF2 di tabel
// game_google_player_credentials). Setelah register/login server memberi token sesi bertanda tangan HMAC-SHA256
// yang dikirim game sebagai "Authorization: Bearer <token>". Nama function tetap `google-player` agar URL di APK sama.
// Rahasia penanda tangan token: secret function PLAYER_SESSION_SECRET (opsional); bila kosong dipakai turunan dari SUPABASE_SERVICE_ROLE_KEY.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SESSION_SECRET = Deno.env.get("PLAYER_SESSION_SECRET") ?? SUPABASE_SERVICE_ROLE_KEY;
const SESSION_TTL_SECONDS = 180 * 24 * 60 * 60; // 180 hari
const MAX_FAILED_LOGINS = 5;
const LOCK_MINUTES = 5;
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

// Identitas pemain yang dipakai semua aksi. `sub` hanyalah kunci internal tabel (akun baru: "local:<uuid>").
type Identity = { sub: string; email: string; email_verified: boolean; name: string; picture: string; player_uuid: string };

function identityFromPlayer(p: Record<string, any>): Identity {
  return {
    sub: String(p.google_sub),
    email: String(p.email),
    email_verified: true,
    name: String(p.nickname ?? p.google_name ?? "Pemain"),
    picture: String(p.avatar_url ?? ""),
    player_uuid: String(p.player_uuid),
  };
}

// ---------------- token sesi (HMAC-SHA256) ----------------
const encoder = new TextEncoder();
function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
function b64urlDecode(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  const raw = atob(padded);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}
async function hmacSign(data: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode("kic-player-session:" + SESSION_SECRET),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64url(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(data))));
}
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
async function issueSessionToken(playerUuid: string): Promise<string> {
  const payload = b64url(encoder.encode(JSON.stringify({
    u: playerUuid, e: Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS, v: 1,
  })));
  return `kic1.${payload}.${await hmacSign("kic1." + payload)}`;
}

async function verifySession(request: Request): Promise<Identity> {
  const header = request.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw Object.assign(new Error("Silakan masuk terlebih dahulu."), { status: 401 });
  const parts = match[1].trim().split(".");
  if (parts.length !== 3 || parts[0] !== "kic1" || parts[1].length > 512) {
    throw Object.assign(new Error("Sesi tidak valid. Silakan masuk kembali."), { status: 401 });
  }
  const expected = await hmacSign("kic1." + parts[1]);
  if (!safeEqual(expected, parts[2])) throw Object.assign(new Error("Sesi tidak valid. Silakan masuk kembali."), { status: 401 });
  let claims: { u?: unknown; e?: unknown };
  try { claims = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1]))); }
  catch (_) { throw Object.assign(new Error("Sesi tidak valid. Silakan masuk kembali."), { status: 401 }); }
  if (typeof claims.u !== "string" || typeof claims.e !== "number" || claims.e <= Math.floor(Date.now() / 1000)) {
    throw Object.assign(new Error("Sesi sudah berakhir. Silakan masuk kembali."), { status: 401 });
  }
  const { data, error } = await service.from("game_google_players")
    .select("player_uuid,google_sub,email,nickname,google_name,avatar_url,profile_completed")
    .eq("player_uuid", claims.u).maybeSingle();
  if (error) throw new Error("Pemeriksaan akun pemain gagal.");
  if (!data || !(data as any).profile_completed) {
    throw Object.assign(new Error("Akun tidak ditemukan. Silakan masuk kembali."), { status: 401 });
  }
  return identityFromPlayer(data as Record<string, any>);
}

async function requireData<T = unknown>(query: PromiseLike<{ data: T | null; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await query;
  if (error) throw Object.assign(new Error(error.message), { status: 500 });
  return data as T;
}

async function loadWallet(playerUuid: string) {
  const economy = await requireData<any>(service.from("game_google_player_economy").upsert({
    player_uuid: playerUuid,
  }, { onConflict: "player_uuid", ignoreDuplicates: true }).select("*").maybeSingle());
  return economy || await requireData<any>(service.from("game_google_player_economy").select("*").eq("player_uuid", playerUuid).single());
}

// Profil + saldo akun yang sedang masuk (token sesi sudah diverifikasi).
async function bootstrap(identity: Identity) {
  const profile = await requireData<any>(service.from("game_google_players")
    .update({ last_seen_at: new Date().toISOString(), updated_at: new Date().toISOString() })
    .eq("player_uuid", identity.player_uuid).select("*").single());
  return { profile, economy: await loadWallet(identity.player_uuid) };
}

const PASSWORD_ITERATIONS = 100_000;
function toHex(bytes: Uint8Array) { return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(""); }
function fromHex(hex: string) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}
async function hashPassword(password: string, salt: Uint8Array, iterations = PASSWORD_ITERATIONS) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, key, 256);
  return toHex(new Uint8Array(bits));
}

function readCredentials(body: Record<string, unknown>) {
  const nickname = typeof body.nickname === "string" ? body.nickname.trim() : "";
  if (nickname.length < 3 || nickname.length > 32) throw new Error("Nama pengguna harus terdiri dari 3–32 karakter.");
  if (!/^[\p{L}\p{N} _.-]+$/u.test(nickname)) throw new Error("Nama pengguna hanya boleh memakai huruf, angka, spasi, titik, garis bawah, atau tanda hubung.");
  const password = typeof body.password === "string" ? body.password : "";
  if (password.length < 4 || password.length > 16) throw new Error("Kata sandi harus 4–16 karakter.");
  return { nickname, password };
}
const escapeLike = (text: string) => text.replace(/[\\%_]/g, "\\$&");

// Daftar akun baru: nama pengguna unik (tanpa membedakan huruf besar/kecil) + kata sandi.
async function registerPlayer(body: Record<string, unknown>) {
  const { nickname, password } = readCredentials(body);
  const taken = await requireData<any>(service.from("game_google_players").select("player_uuid")
    .ilike("nickname", escapeLike(nickname)).maybeSingle());
  if (taken) throw new Error("Nama pengguna sudah dipakai. Pilih nama lain.");

  const uid = crypto.randomUUID();
  let player: any;
  try {
    player = await requireData<any>(service.from("game_google_players").insert({
      google_sub: `local:${uid}`,
      email: `pemain-${uid}@akun.dtp.local`,
      email_verified: true,
      google_name: nickname,
      avatar_url: "",
      nickname,
      profile_completed: true,
      last_seen_at: new Date().toISOString(),
    }).select("*").single());
  } catch (e) {
    if (/duplicate key|nickname_ci_uq/i.test((e as Error).message)) throw new Error("Nama pengguna sudah dipakai. Pilih nama lain.");
    throw e;
  }
  try {
    // Kata sandi tidak pernah disimpan polos: hanya hash PBKDF2-SHA256 + salt acak, di tabel khusus service_role.
    const salt = crypto.getRandomValues(new Uint8Array(16));
    await requireData<any>(service.from("game_google_player_credentials").insert({
      player_uuid: player.player_uuid,
      password_hash: await hashPassword(password, salt),
      password_salt: toHex(salt),
      password_iterations: PASSWORD_ITERATIONS,
    }).select("player_uuid").single());
  } catch (e) {
    await service.from("game_google_players").delete().eq("player_uuid", player.player_uuid);
    throw e;
  }
  const economy = await loadWallet(player.player_uuid);
  return { player, result: { token: await issueSessionToken(player.player_uuid), profile: player, economy } };
}

// Masuk: nama pengguna + kata sandi. Pesan salah dibuat sama agar nama pengguna tidak bisa ditebak.
async function loginPlayer(body: Record<string, unknown>) {
  const nickname = typeof body.nickname === "string" ? body.nickname.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (nickname.length < 3 || nickname.length > 32 || password.length < 4 || password.length > 16) {
    throw Object.assign(new Error("Nama pengguna atau kata sandi salah."), { status: 401 });
  }
  const wrong = () => Object.assign(new Error("Nama pengguna atau kata sandi salah."), { status: 401 });
  const player = await requireData<any>(service.from("game_google_players").select("*")
    .ilike("nickname", escapeLike(nickname)).eq("profile_completed", true).maybeSingle());
  if (!player) {
    await hashPassword(password, new Uint8Array(16)); // samakan waktu respons
    throw wrong();
  }
  const cred = await requireData<any>(service.from("game_google_player_credentials").select("*")
    .eq("player_uuid", player.player_uuid).maybeSingle());
  if (!cred) throw wrong();
  if (cred.locked_until && Date.parse(cred.locked_until) > Date.now()) {
    throw Object.assign(new Error(`Terlalu banyak percobaan salah. Coba lagi dalam ${LOCK_MINUTES} menit.`), { status: 429 });
  }
  const hash = await hashPassword(password, fromHex(String(cred.password_salt)), Number(cred.password_iterations) || PASSWORD_ITERATIONS);
  if (!safeEqual(hash, String(cred.password_hash))) {
    const failed = Number(cred.failed_attempts ?? 0) + 1;
    const lock = failed >= MAX_FAILED_LOGINS;
    await service.from("game_google_player_credentials").update({
      failed_attempts: lock ? 0 : failed,
      locked_until: lock ? new Date(Date.now() + LOCK_MINUTES * 60_000).toISOString() : null,
    }).eq("player_uuid", player.player_uuid);
    throw wrong();
  }
  if (cred.failed_attempts || cred.locked_until) {
    await service.from("game_google_player_credentials").update({ failed_attempts: 0, locked_until: null })
      .eq("player_uuid", player.player_uuid);
  }
  const economy = await loadWallet(player.player_uuid);
  return { player, result: { token: await issueSessionToken(player.player_uuid), profile: player, economy } };
}


async function getPlayerInbox(identity: Identity) {
  const player = await requireData<any>(service.from("game_google_players")
    .select("player_uuid,email").eq("google_sub", identity.sub).single());
  const messages = await requireData<any[]>(service.from("game_google_player_mail")
    .select("mail_id,subject,message,reward_config,created_at,expires_at,claimed_at,claim_result,admin_name")
    .eq("player_uuid", player.player_uuid)
    .order("created_at", { ascending: false }).limit(100));
  return { messages };
}

async function claimPlayerMail(identity: Identity, body: Record<string, unknown>) {
  const mailId = typeof body.mail_id === "string" ? body.mail_id.trim() : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(mailId)) {
    throw new Error("ID surat tidak valid.");
  }
  return await requireData<any>(service.rpc("game_google_claim_player_mail", {
    p_google_sub: identity.sub,
    p_mail_id: mailId,
  }));
}

async function syncNativeWallet(identity: Identity, body: Record<string, unknown>) {
  const integer = (key: string, max = 2147483647) => {
    const value = Number(body[key]);
    if (!Number.isSafeInteger(value) || value < 0 || value > max) throw new Error(`Saldo native ${key} tidak valid.`);
    return value;
  };
  const coins = integer("coins");
  const crystals = integer("crystals");
  const goblinCoins = integer("goblin_coins");
  const meat = integer("meat", 24);
  const player = await requireData<any>(service.from("game_google_players")
    .select("player_uuid,email,last_seen_at").eq("google_sub", identity.sub).single());
  const prior = await requireData<any>(service.from("game_google_player_native_wallets")
    .select("coins,crystals,goblin_coins,meat").eq("player_uuid", player.player_uuid).maybeSingle());
  const changed = !prior || prior.coins !== coins || prior.crystals !== crystals || prior.goblin_coins !== goblinCoins || prior.meat !== meat;
  const now = new Date().toISOString();
  const snapshot = await requireData<any>(service.from("game_google_player_native_wallets").upsert({
    player_uuid: player.player_uuid,
    coins,
    crystals,
    goblin_coins: goblinCoins,
    meat,
    client_observed_at: now,
    server_received_at: now,
  }, { onConflict: "player_uuid" }).select("player_uuid,coins,crystals,goblin_coins,meat,client_observed_at,server_received_at").single());
  if (changed) {
    const { error } = await service.from("game_google_activity").insert({
      actor_type: "player", player_uuid: player.player_uuid, actor_email: identity.email,
      action: "native_wallet_observed", details: { coins, crystals, goblin_coins: goblinCoins, meat },
    });
    if (error) console.warn("Native wallet activity log failed:", error.message);
  }
  // v17.14.21: APK melapor tiap 2 detik. Dashboard admin hanya dibangunkan bila saldo berubah, atau sebagai
  // denyut jantung tiap 10 detik (memperbarui last_seen), supaya tidak membanjiri broadcast/tabel.
  const lastSeen = Date.parse(player.last_seen_at ?? "") || 0;
  const notify = changed || !prior || Date.now() - lastSeen >= 10000;
  return { native_wallet: snapshot, authoritative: false, changed, notify };
}

// v17.14.20: hadiah admin masuk otomatis. Layar Surat dihapus di v17.14.19, jadi server sendiri mengklaim
// surat berhadiah milik pemain (kredit ke saldo server lewat RPC yang sama), lalu mengembalikan SEMUA klaim
// (surat + kode hadiah) agar APK memasukkannya ke saldo native game. APK menjaga anti-ganda lewat claim_id.
async function pullRewards(identity: Identity) {
  const player = await requireData<any>(service.from("game_google_players")
    .select("player_uuid,email").eq("google_sub", identity.sub).single());

  const pending = await requireData<any[]>(service.from("game_google_player_mail")
    .select("mail_id,reward_config,expires_at").eq("player_uuid", player.player_uuid)
    .is("claimed_at", null).order("created_at", { ascending: true }).limit(25));
  let autoClaimed = 0;
  const failed: string[] = [];
  for (const mail of pending) {
    if (mail.expires_at && Date.parse(mail.expires_at) <= Date.now()) continue;
    const reward = isObject(mail.reward_config) ? mail.reward_config : {};
    if (!Object.values(reward).some((v) => Number(v) > 0)) continue; // surat tanpa hadiah: tidak perlu klaim
    try {
      await requireData<any>(service.rpc("game_google_claim_player_mail", {
        p_google_sub: identity.sub, p_mail_id: mail.mail_id,
      }));
      autoClaimed++;
      const { error } = await service.from("game_google_activity").insert({
        actor_type: "player", player_uuid: player.player_uuid, actor_email: identity.email,
        action: "mail_claimed", details: { mail_id: mail.mail_id, reward_config: reward, auto: true },
      });
      if (error) console.warn("Auto-claim activity log failed:", error.message);
    } catch (error) {
      failed.push(`${mail.mail_id}: ${(error as Error).message}`);
    }
  }

  const mails = await requireData<any[]>(service.from("game_google_player_mail")
    .select("mail_id,reward_config,claim_result,claimed_at").eq("player_uuid", player.player_uuid)
    .not("claimed_at", "is", null).order("claimed_at", { ascending: false }).limit(100));
  const codes = await requireData<any[]>(service.from("game_reward_code_claims")
    .select("claim_id,reward_applied,claimed_at").eq("player_uuid", player.player_uuid)
    .eq("native_credit", true).order("claimed_at", { ascending: false }).limit(100));
  const claims = [
    ...mails.map((m) => ({ claim_id: m.mail_id, source: "mail", rewards: m.claim_result ?? m.reward_config, claimed_at: m.claimed_at })),
    ...codes.map((c) => ({ claim_id: c.claim_id, source: "code", rewards: c.reward_applied, claimed_at: c.claimed_at })),
  ];
  return { claims, auto_claimed: autoClaimed, failed };
}

// v17.14.21: pastikan jawaban redeem_code SELALU membawa { claim: { claim_id, code, rewards } }.
async function ensureClaimPayload(identity: Identity, code: string, redeemed: any) {
  const base = isObject(redeemed) ? redeemed : {};
  const existing = (base as any).claim;
  if (isObject(existing) && isObject((existing as any).rewards) && (existing as any).claim_id) return base;
  const { data: player } = await service.from("game_google_players")
    .select("player_uuid").eq("google_sub", identity.sub).maybeSingle();
  const { data: codeRow } = await service.from("game_reward_codes")
    .select("code_id,reward_config").eq("code", code).maybeSingle();
  if (!player || !codeRow) return base;
  const { data: claimRow } = await service.from("game_reward_code_claims")
    .select("claim_id,reward_applied").eq("player_uuid", (player as any).player_uuid)
    .eq("code_id", (codeRow as any).code_id).maybeSingle();
  if (!claimRow) return base;
  const rewards = isObject((claimRow as any).reward_applied) && Object.keys((claimRow as any).reward_applied).length > 0
    ? (claimRow as any).reward_applied : (codeRow as any).reward_config;
  return { ...(base as Record<string, unknown>), claim: { claim_id: (claimRow as any).claim_id, code, rewards } };
}

async function notifyAdminDashboard(identity: Identity, resource: string) {
  const { data: player, error } = await service.from("game_google_players")
    .select("player_uuid,email").eq("google_sub", identity.sub).maybeSingle();
  if (error || !player) return false;
  const now = new Date().toISOString();
  // Perbarui last_seen pada setiap permintaan bersesi. Detak jantung saldo native tiap 10 detik
  // membuat dashboard admin selalu melihat status pemain terbaru.
  const { error: profileRefreshError } = await service.from("game_google_players").update({
    email: identity.email,
    email_verified: identity.email_verified,
    google_name: identity.name,
    avatar_url: identity.picture,
    last_seen_at: now,
    updated_at: now,
  }).eq("player_uuid", player.player_uuid);
  if (profileRefreshError) console.warn("Player profile refresh failed:", profileRefreshError.message);
  const activityActions: Record<string, string> = {
    bootstrap: "google_login", complete_profile: "profile_completed",
    buy_meat: "meat_purchased", consume_meat: "meat_consumed",
    redeem_code: "reward_code_claimed", claim_mail: "mail_claimed",
  };
  const activity = activityActions[resource];
  if (activity) {
    const { error: activityError } = await service.from("game_google_activity").insert({
      actor_type: "player", player_uuid: player.player_uuid, actor_email: identity.email,
      action: activity, details: { source_action: resource },
    });
    if (activityError) console.warn("Player activity log failed:", activityError.message);
  }
  const channel = service.channel("google-admin-dashboard");
  try {
    return (await channel.send({
      type: "broadcast",
      event: "google_player_changed",
      payload: { player_uuid: player.player_uuid, resource, updated_at: now },
    })) === "ok";
  } catch (error) {
    console.warn("Player admin broadcast failed:", error);
    return false;
  } finally {
    try { await service.removeChannel(channel); } catch (_) { }
  }
}

// ---------------- v17.14.17: jalur baca Boss Gua & Event Shop untuk pemain ----------------
// Sebelumnya game memanggil RPC lewat sesi Supabase Auth lama. Sesi itu tidak ada lagi setelah
// sesi Supabase Auth, sehingga perintah admin tidak pernah terbaca game. Aksi di bawah hanya
// BACA (tidak mengubah apa pun) dan sengaja tidak memicu notifyAdminDashboard supaya polling
// berkala dari game tidak membanjiri tabel aktivitas / broadcast admin.
async function requireKnownPlayer(identity: Identity) {
  const { data, error } = await service.from("game_google_players")
    .select("player_uuid").eq("google_sub", identity.sub).maybeSingle();
  if (error) throw new Error("Pemeriksaan akun pemain gagal.");
  if (!data) throw Object.assign(new Error("Akun belum terdaftar sebagai pemain. Masuk ulang lewat tombol LOGIN di game."), { status: 403 });
  return data as { player_uuid: string };
}

async function getCaveBossForPlayer(identity: Identity) {
  await requireKnownPlayer(identity);
  // get_active_cave_boss() tidak bergantung pada auth.uid() dan sudah di-grant ke service_role.
  const { data, error } = await service.rpc("get_active_cave_boss");
  if (error) {
    console.error("get_active_cave_boss failed:", error.message);
    throw new Error("Data Boss Gua belum tersedia di server. Jalankan SQL v16 di Supabase.");
  }
  return data ?? { active: false };
}

async function getEventStoreForPlayer(identity: Identity) {
  const player = await requireKnownPlayer(identity);
  const { data, error } = await service.rpc("game_google_active_event_store", { p_player_uuid: player.player_uuid });
  if (error) {
    console.error("game_google_active_event_store failed:", error.message);
    throw new Error("Data Event Shop belum tersedia di server. Jalankan SQL v17.14.17 di Supabase.");
  }
  return data ?? { active: false, items: [] };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return fail("Method not allowed", 405);
  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("Konfigurasi server database belum lengkap.");
    const body = await request.json().catch(() => ({}));
    if (!isObject(body)) return fail("Request body tidak valid.");
    const action = String(body.action ?? "");

    // v1.0.9: cek kesehatan server tanpa sesi. Buka lewat tombol "Test" di Supabase atau curl; harus ok:true.
    if (action === "ping") {
      const checks: Record<string, string> = {};
      for (const table of ["game_google_players", "game_google_player_credentials", "game_google_player_economy", "game_google_player_mail"]) {
        const { error } = await service.from(table).select("*", { head: true, count: "exact" }).limit(1);
        checks[table] = error ? `GAGAL: ${error.message}` : "ok";
      }
      const { error: colError } = await service.from("game_google_player_credentials").select("failed_attempts,locked_until").limit(1);
      checks["credentials.failed_attempts/locked_until"] = colError ? `GAGAL: ${colError.message}` : "ok";
      const allOk = Object.values(checks).every((v) => v === "ok");
      return json({ ok: allOk, data: { version: "1.0.9-password", login: "nama pengguna + kata sandi", checks } }, allOk ? 200 : 500);
    }

    // Aksi tanpa sesi: daftar & masuk. Hasilnya berisi token sesi untuk permintaan berikutnya.
    if (action === "register" || action === "login") {
      const done = action === "register" ? await registerPlayer(body) : await loginPlayer(body);
      await notifyAdminDashboard(identityFromPlayer(done.player), action === "register" ? "complete_profile" : "bootstrap");
      return json({ ok: true, data: done.result });
    }

    const identity = await verifySession(request);
    let data: unknown;
    // v17.14.17: aksi baca-saja tidak memperbarui last_seen / tidak membroadcast ke dashboard.
    let readOnlyPoll = false;

    if (action === "bootstrap") {
      data = await bootstrap(identity);
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
      const redeemed = await requireData<any>(service.rpc("game_google_redeem_reward_code", { p_google_sub: identity.sub, p_code: code }));
      // v17.14.21: APK memasukkan hadiah ke saldo game dari objek `claim`. Bila SQL di Supabase masih versi lama
      // (RPC tidak mengembalikan `claim`), ambil klaim yang baru saja dibuat agar hadiah tetap masuk ke game.
      data = await ensureClaimPayload(identity, code, redeemed);
    } else if (action === "get_code_claims") {
      // v17.14.19: klaim kode hadiah terbaru yang hadiahnya harus masuk ke saldo native (pemulihan).
      const player = await requireData<any>(service.from("game_google_players")
        .select("player_uuid").eq("google_sub", identity.sub).single());
      const claims = await requireData<any[]>(service.from("game_reward_code_claims")
        .select("claim_id, reward_applied, claimed_at").eq("player_uuid", player.player_uuid)
        .eq("native_credit", true).order("claimed_at", { ascending: false }).limit(100));
      data = { claims };
      readOnlyPoll = true;
    } else if (action === "pull_rewards") {
      const pulled = await pullRewards(identity);
      data = pulled;
      // Hanya memicu dashboard admin bila ada surat yang baru diklaim; polling kosong tetap senyap.
      readOnlyPoll = pulled.auto_claimed === 0;
    } else if (action === "get_mail") {
      data = await getPlayerInbox(identity);
    } else if (action === "claim_mail") {
      data = await claimPlayerMail(identity, body);
    } else if (action === "sync_native_wallet") {
      data = await syncNativeWallet(identity, body);
      readOnlyPoll = !(data as { notify?: boolean }).notify;
    } else if (action === "get_cave_boss") {
      data = await getCaveBossForPlayer(identity);
      readOnlyPoll = true;
    } else if (action === "get_event_store") {
      data = await getEventStoreForPlayer(identity);
      readOnlyPoll = true;
    } else {
      return fail("Aksi pemain tidak dikenal.", 404);
    }
    // Every authenticated player request updates last-seen and invalidates the admin snapshot.
    // The dashboard also polls as a fallback if the broadcast is temporarily missed.
    if (!readOnlyPoll) await notifyAdminDashboard(identity, action);
    return json({ ok: true, data });
  } catch (error) {
    const e = error as Error & { status?: number };
    console.error("google-player action failed:", e.message);
    return fail(e.message || "Permintaan pemain gagal.", e.status ?? 400);
  }
});
