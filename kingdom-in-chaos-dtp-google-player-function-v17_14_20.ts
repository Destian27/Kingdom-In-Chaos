// v17.14.17: tambah aksi get_cave_boss & get_event_store agar perintah admin (Boss Gua / Event Shop) sampai ke pemain login Google langsung.
// v17.14.16: Daftar = Nama Pengguna + Kata Sandi (4-16, disimpan sebagai hash PBKDF2 di tabel terpisah).
// v17.14.9: Android OAuth client ID (com.destian.kingdominchaosdtp + SHA-1 dtp-fixed.keystore) dipasang sebagai default.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Public Web OAuth client ID: safe to expose as an audience identifier.
// It is used only to validate Google ID tokens (aud claim).
const GOOGLE_WEB_OAUTH_CLIENT_ID = Deno.env.get("GOOGLE_WEB_OAUTH_CLIENT_ID") ??
  "709171564273-tgg9tklkjsp02tovhganpdr3cqspnc2r.apps.googleusercontent.com";
// Optional Android OAuth client ID. Set this separately to the client created
// for package com.destian.kingdominchaosdtp + the release signing SHA-1.
const GOOGLE_ANDROID_OAUTH_CLIENT_ID = Deno.env.get("GOOGLE_ANDROID_OAUTH_CLIENT_ID") ??
  "709171564273-sk6tcg5nk2tk13lghb1hb4sc1he3c7me.apps.googleusercontent.com";
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

function googleIdentityFromClaims(claims: Record<string, unknown>) {
  const verified = claims.email_verified === true || claims.email_verified === "true";
  if (!claims.sub || !claims.email || !verified) {
    throw Object.assign(new Error("Email Google harus sudah terverifikasi."), { status: 403 });
  }
  return {
    sub: String(claims.sub),
    email: String(claims.email).trim().toLowerCase(),
    email_verified: true,
    name: String(claims.name ?? claims.given_name ?? "Pemain Google").slice(0, 120),
    picture: String(claims.picture ?? "").slice(0, 2048),
  };
}

async function verifyGoogleIdToken(token: string) {
  if (!GOOGLE_WEB_OAUTH_CLIENT_ID) {
    throw Object.assign(new Error("Google Web OAuth Client ID belum dikonfigurasi di server."), { status: 503 });
  }
  const infoUrl = new URL("https://oauth2.googleapis.com/tokeninfo");
  infoUrl.searchParams.set("id_token", token);
  const response = await fetch(infoUrl);
  if (!response.ok) throw Object.assign(new Error("Google ID token tidak valid atau kedaluwarsa."), { status: 401 });
  const claims = await response.json() as Record<string, unknown>;
  const issuer = String(claims.iss ?? "");
  const expiry = Number(claims.exp ?? 0);
  if (String(claims.aud ?? "") !== GOOGLE_WEB_OAUTH_CLIENT_ID ||
      !["accounts.google.com", "https://accounts.google.com"].includes(issuer) ||
      !Number.isFinite(expiry) || expiry <= Math.floor(Date.now() / 1000)) {
    throw Object.assign(new Error("Token Google bukan untuk aplikasi Kingdom In Chaos DTP atau sudah kedaluwarsa."), { status: 401 });
  }
  return googleIdentityFromClaims(claims);
}

async function verifyGoogleAccessToken(request: Request) {
  const header = request.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw Object.assign(new Error("Login Google diperlukan."), { status: 401 });
  const token = match[1].trim();
  if (token.length < 30 || token.length > 8192) throw Object.assign(new Error("Token Google tidak valid."), { status: 401 });

  // Accept an ID token issued for the configured Web OAuth client. The client
  // secret is deliberately not required for ID-token verification.
  if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) return await verifyGoogleIdToken(token);

  // Current Android build obtains a Google access token from Google Play
  // Services. Google userinfo validates it and returns the verified identity.
  const response = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw Object.assign(new Error("Sesi Google tidak valid atau sudah kedaluwarsa. Silakan login ulang."), { status: 401 });
  const user = await response.json() as Record<string, unknown>;
  const identity = googleIdentityFromClaims(user);

  // Pin access tokens to the Android client only when that Android OAuth ID
  // is configured. Do not compare Android access tokens to the Web client ID.
  if (GOOGLE_ANDROID_OAUTH_CLIENT_ID) {
    const infoUrl = new URL("https://oauth2.googleapis.com/tokeninfo");
    infoUrl.searchParams.set("access_token", token);
    const infoResponse = await fetch(infoUrl);
    if (!infoResponse.ok) throw Object.assign(new Error("Tidak dapat memverifikasi aplikasi Google."), { status: 401 });
    const info = await infoResponse.json() as Record<string, unknown>;
    const issuedTo = String(info.issued_to ?? info.aud ?? "");
    if (!issuedTo || issuedTo !== GOOGLE_ANDROID_OAUTH_CLIENT_ID) {
      throw Object.assign(new Error("Token Google bukan untuk aplikasi Kingdom In Chaos DTP."), { status: 401 });
    }
  }
  return identity;
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
    last_seen_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }, { onConflict: "google_sub" }).select("*").single());
  const economy = await requireData<any>(service.from("game_google_player_economy").upsert({
    player_uuid: profile.player_uuid,
  }, { onConflict: "player_uuid", ignoreDuplicates: true }).select("*").maybeSingle());
  const wallet = economy || await requireData<any>(service.from("game_google_player_economy").select("*").eq("player_uuid", profile.player_uuid).single());
  return { profile, economy: wallet };
}

const PASSWORD_ITERATIONS = 100_000;
function toHex(bytes: Uint8Array) { return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(""); }
async function hashPassword(password: string, salt: Uint8Array, iterations = PASSWORD_ITERATIONS) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, key, 256);
  return toHex(new Uint8Array(bits));
}

async function completeProfile(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>, body: Record<string, unknown>) {
  const nickname = typeof body.nickname === "string" ? body.nickname.trim() : "";
  if (nickname.length < 3 || nickname.length > 32) throw new Error("Nama pengguna harus terdiri dari 3–32 karakter.");
  if (!/^[\p{L}\p{N} _.-]+$/u.test(nickname)) throw new Error("Nama pengguna hanya boleh memakai huruf, angka, spasi, titik, garis bawah, atau tanda hubung.");
  const password = typeof body.password === "string" ? body.password : "";
  if (password.length < 4 || password.length > 16) throw new Error("Kata sandi harus 4–16 karakter.");

  const current = await requireData<any>(service.from("game_google_players").select("*").eq("google_sub", identity.sub).single());
  if (current.profile_completed) throw new Error("Akun ini sudah terdaftar.");

  const taken = await requireData<any>(service.from("game_google_players").select("player_uuid")
    .ilike("nickname", nickname.replace(/[\\%_]/g, "\\$&")).neq("player_uuid", current.player_uuid).maybeSingle());
  if (taken) throw new Error("Nama pengguna sudah dipakai. Pilih nama lain.");

  // Kata sandi tidak pernah disimpan polos: hanya hash PBKDF2-SHA256 + salt acak, di tabel khusus service_role.
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await hashPassword(password, salt);
  await requireData<any>(service.from("game_google_player_credentials").upsert({
    player_uuid: current.player_uuid,
    password_hash: hash,
    password_salt: toHex(salt),
    password_iterations: PASSWORD_ITERATIONS,
    updated_at: new Date().toISOString(),
  }, { onConflict: "player_uuid" }).select("player_uuid").single());

  let profile: any;
  try {
    profile = await requireData<any>(service.from("game_google_players").update({
      nickname,
      profile_completed: true,
      updated_at: new Date().toISOString(),
    }).eq("player_uuid", current.player_uuid).eq("profile_completed", false).select("*").single());
  } catch (e) {
    if (/duplicate key|nickname_ci_uq/i.test((e as Error).message)) throw new Error("Nama pengguna sudah dipakai. Pilih nama lain.");
    throw e;
  }
  const economy = await requireData<any>(service.from("game_google_player_economy").select("*").eq("player_uuid", current.player_uuid).single());
  return { profile, economy };
}


async function getPlayerInbox(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>) {
  const player = await requireData<any>(service.from("game_google_players")
    .select("player_uuid,email").eq("google_sub", identity.sub).single());
  const messages = await requireData<any[]>(service.from("game_google_player_mail")
    .select("mail_id,subject,message,reward_config,created_at,expires_at,claimed_at,claim_result,admin_name")
    .eq("player_uuid", player.player_uuid)
    .order("created_at", { ascending: false }).limit(100));
  return { messages };
}

async function claimPlayerMail(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>, body: Record<string, unknown>) {
  const mailId = typeof body.mail_id === "string" ? body.mail_id.trim() : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(mailId)) {
    throw new Error("ID surat tidak valid.");
  }
  return await requireData<any>(service.rpc("game_google_claim_player_mail", {
    p_google_sub: identity.sub,
    p_mail_id: mailId,
  }));
}

async function syncNativeWallet(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>, body: Record<string, unknown>) {
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
    .select("player_uuid,email").eq("google_sub", identity.sub).single());
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
  return { native_wallet: snapshot, authoritative: false };
}

// v17.14.20: hadiah admin masuk otomatis. Layar Surat dihapus di v17.14.19, jadi server sendiri mengklaim
// surat berhadiah milik pemain (kredit ke saldo server lewat RPC yang sama), lalu mengembalikan SEMUA klaim
// (surat + kode hadiah) agar APK memasukkannya ke saldo native game. APK menjaga anti-ganda lewat claim_id.
async function pullRewards(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>) {
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

async function notifyGoogleAdminDashboard(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>, resource: string) {
  const { data: player, error } = await service.from("game_google_players")
    .select("player_uuid,email").eq("google_sub", identity.sub).maybeSingle();
  if (error || !player) return false;
  const now = new Date().toISOString();
  // Refresh the Google identity fields on every verified request. The foreground
  // native-wallet heartbeat runs every 10 seconds, so a changed Google profile
  // photo/name/email is copied to the admin dashboard without requiring a relogin.
  const { error: profileRefreshError } = await service.from("game_google_players").update({
    email: identity.email,
    email_verified: identity.email_verified,
    google_name: identity.name,
    avatar_url: identity.picture,
    last_seen_at: now,
    updated_at: now,
  }).eq("player_uuid", player.player_uuid);
  if (profileRefreshError) console.warn("Google profile refresh failed:", profileRefreshError.message);
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
    console.warn("Google player admin broadcast failed:", error);
    return false;
  } finally {
    try { await service.removeChannel(channel); } catch (_) { }
  }
}

// ---------------- v17.14.17: jalur baca Boss Gua & Event Shop untuk pemain Google ----------------
// Sebelumnya game memanggil RPC lewat sesi Supabase Auth lama. Sesi itu tidak ada lagi setelah
// login Google langsung, sehingga perintah admin tidak pernah terbaca game. Aksi di bawah hanya
// BACA (tidak mengubah apa pun) dan sengaja tidak memicu notifyGoogleAdminDashboard supaya polling
// berkala dari game tidak membanjiri tabel aktivitas / broadcast admin.
async function requireKnownPlayer(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>) {
  const { data, error } = await service.from("game_google_players")
    .select("player_uuid").eq("google_sub", identity.sub).maybeSingle();
  if (error) throw new Error("Pemeriksaan akun pemain gagal.");
  if (!data) throw Object.assign(new Error("Akun Google belum terdaftar sebagai pemain. Login ulang lewat tombol ONLINE."), { status: 403 });
  return data as { player_uuid: string };
}

async function getCaveBossForPlayer(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>) {
  await requireKnownPlayer(identity);
  // get_active_cave_boss() tidak bergantung pada auth.uid() dan sudah di-grant ke service_role.
  const { data, error } = await service.rpc("get_active_cave_boss");
  if (error) {
    console.error("get_active_cave_boss failed:", error.message);
    throw new Error("Data Boss Gua belum tersedia di server. Jalankan SQL v16 di Supabase.");
  }
  return data ?? { active: false };
}

async function getEventStoreForPlayer(identity: Awaited<ReturnType<typeof verifyGoogleAccessToken>>) {
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
    const identity = await verifyGoogleAccessToken(request);
    const body = await request.json().catch(() => ({}));
    if (!isObject(body)) return fail("Request body tidak valid.");
    const action = String(body.action ?? "");
    let data: unknown;
    // v17.14.17: aksi baca-saja tidak memperbarui last_seen / tidak membroadcast ke dashboard.
    let readOnlyPoll = false;

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
    if (!readOnlyPoll) await notifyGoogleAdminDashboard(identity, action);
    return json({ ok: true, data });
  } catch (error) {
    const e = error as Error & { status?: number };
    console.error("google-player action failed:", e.message);
    return fail(e.message || "Permintaan pemain gagal.", e.status ?? 400);
  }
});
