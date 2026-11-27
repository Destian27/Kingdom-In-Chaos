import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders });
}
function fail(message: string, status = 400) {
  return json({ ok: false, error: message }, status);
}
function isObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
function cleanText(value: unknown, min: number, max: number, name: string): string {
  if (typeof value !== "string") throw new Error(`${name} wajib berupa teks.`);
  const v = value.trim();
  if (v.length < min || v.length > max) throw new Error(`${name} harus ${min}-${max} karakter.`);
  return v;
}
function uuid(value: unknown, name = "User ID"): string {
  const v = typeof value === "string" ? value.trim() : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v)) {
    throw new Error(`${name} tidak valid.`);
  }
  return v;
}
type AdminAuthUser = { id: string; [key: string]: unknown };

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing one or more Supabase function environment variables.");
}

const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/**
 * Send a small invalidation event through Supabase Realtime Broadcast.
 * The client then reloads the authenticated RPC snapshot; no player data or
 * service-role credentials are included in the broadcast payload.
 * Postgres Changes remains enabled as a second delivery path.
 */
async function publishRealtimeBroadcast(
  topic: string,
  event: string,
  payload: Record<string, unknown>,
): Promise<boolean> {
  const channel = service.channel(topic);
  try {
    const status = await channel.send({ type: "broadcast", event, payload });
    if (status !== "ok") {
      console.warn(`Realtime broadcast not acknowledged (${topic}/${event}):`, status);
      return false;
    }
    return true;
  } catch (error) {
    console.warn(`Realtime broadcast failed (${topic}/${event}):`, error);
    return false;
  } finally {
    try { await service.removeChannel(channel); } catch (error) {
      console.warn("Realtime channel cleanup failed:", error);
    }
  }
}

async function notifyPlayerStateChanged(targetId: string, resource: string) {
  return await publishRealtimeBroadcast(`player-state-${targetId}`, "player_state_updated", {
    resource,
    updated_at: new Date().toISOString(),
  });
}

async function sha256(value: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}
function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
async function verifyMaintenanceCredentials(value: unknown): Promise<boolean> {
  if (!isObject(value)) return false;
  const configuredName = Deno.env.get("MAINTENANCE_ADMIN_NAME") ?? "";
  const configuredPassword = Deno.env.get("MAINTENANCE_ADMIN_PASSWORD") ?? "";
  const suppliedName = typeof value.name === "string" ? value.name : "";
  const suppliedPassword = typeof value.password === "string" ? value.password : "";
  if (!configuredName || !configuredPassword || !suppliedName || !suppliedPassword) return false;
  const [a, b, c, d] = await Promise.all([
    sha256(configuredName), sha256(suppliedName),
    sha256(configuredPassword), sha256(suppliedPassword),
  ]);
  return constantTimeEqual(a, b) && constantTimeEqual(c, d);
}

async function requireAdmin(request: Request, body: Record<string, unknown>) {
  // Preferred: reuse the already authenticated first maintenance-admin session.
  if (await verifyMaintenanceCredentials(body.admin_credentials)) {
    let query = service.from("game_admin_users")
      .select("user_id, role, active")
      .eq("active", true);
    const pinnedId = Deno.env.get("MAINTENANCE_ADMIN_USER_ID") ?? "";
    if (pinnedId) query = query.eq("user_id", pinnedId);
    else query = query.eq("role", "super_admin");
    const { data: adminRow, error: adminError } = await query.limit(1).maybeSingle();
    if (adminError) throw Object.assign(new Error("Pemeriksaan hak admin gagal. Jalankan SQL v17.14 dan pastikan admin aktif."), { status: 503 });
    if (!adminRow) throw Object.assign(new Error("Belum ada super_admin aktif yang terhubung. Atur MAINTENANCE_ADMIN_USER_ID atau bootstrap admin di database."), { status: 403 });
    const { data: authData, error: authError } = await service.auth.admin.getUserById(adminRow.user_id);
    if (authError || !authData.user) throw Object.assign(new Error("Identitas admin database tidak ditemukan."), { status: 403 });
    return { user: authData.user as AdminAuthUser, admin: adminRow };
  }

  // Compatibility path for previously configured Supabase Auth admins.
  const header = request.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw Object.assign(new Error("Sesi admin utama tidak valid. Silakan login kembali."), { status: 401 });
  const token = match[1];
  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !authData.user) throw Object.assign(new Error("Sesi admin tidak valid atau kedaluwarsa."), { status: 401 });
  const { data: adminRow, error: adminError } = await service.from("game_admin_users")
    .select("user_id, role, active").eq("user_id", authData.user.id).eq("active", true).maybeSingle();
  if (adminError) throw Object.assign(new Error("Pemeriksaan hak admin gagal."), { status: 503 });
  if (!adminRow) throw Object.assign(new Error("Akun ini belum diberi akses admin."), { status: 403 });
  return { user: authData.user, admin: adminRow };
}

async function requireData<T = unknown>(query: PromiseLike<{ data: T | null; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await query;
  if (error) {
    console.error("Supabase admin operation failed:", error.message);
    throw Object.assign(new Error("Operasi database gagal. Pastikan SQL All-in-One v17 Realtime sudah dijalankan serta Edge Function game-admin v17 sudah dideploy."), { status: 500 });
  }
  return data as T;
}

// ---------------- Cave Boss hourly schedule (v16) ----------------
const BOSS_DIFFICULTIES = new Set(["normal", "hard", "elite", "nightmare", "custom"]);
function parseBossReward(value: unknown): Record<string, unknown> {
  let parsed: unknown = value;
  if (typeof parsed === "string") {
    try { parsed = JSON.parse(parsed); } catch { throw new Error("Reward harus JSON yang valid."); }
  }
  if (!isObject(parsed)) throw new Error("Reward harus berupa objek JSON, bukan array/null.");
  if (JSON.stringify(parsed).length > 8192) throw new Error("Reward JSON maksimal 8 KB.");
  return parsed;
}
function normalizeBossId(value: unknown, required: boolean): string {
  const v = typeof value === "string" ? value.trim() : "";
  if (!v && !required) return "";
  if (v.length < 1 || v.length > 80 || !/^[A-Za-z0-9_.:-]+$/.test(v)) {
    throw new Error("Boss ID wajib 1-80 karakter dan hanya boleh memakai huruf, angka, titik, garis bawah, titik dua, atau tanda hubung.");
  }
  return v;
}
function normalizeBossName(value: unknown, required: boolean): string {
  const v = typeof value === "string" ? value.trim() : "";
  if (!v && !required) return "";
  if (v.length < 1 || v.length > 120) throw new Error("Nama Boss wajib 1-120 karakter.");
  return v;
}
function normalizeDifficulty(value: unknown): string {
  const v = typeof value === "string" ? value : "normal";
  if (!BOSS_DIFFICULTIES.has(v)) throw new Error("Difficulty Boss tidak valid.");
  return v;
}
function normalizeHpMultiplier(value: unknown): number {
  const v = Number(value ?? 1);
  if (!Number.isFinite(v) || v < 0.1 || v > 10000) throw new Error("Pengali HP harus 0,1 sampai 10.000.");
  return Math.round(v * 1000) / 1000;
}
function normalizeDuration(value: unknown, min: number, max: number): number {
  const v = Number(value);
  if (!Number.isInteger(v) || v < min || v > max) throw new Error(`Durasi harus ${min}-${max} menit.`);
  return v;
}
function normalizeBossHours(raw: unknown): Record<string, unknown>[] {
  if (!Array.isArray(raw) || raw.length !== 24) throw new Error("Jadwal harus memiliki tepat 24 slot jam.");
  const seen = new Set<number>();
  return raw.map((entry) => {
    if (!isObject(entry)) throw new Error("Format slot jadwal Boss tidak valid.");
    const hour = Number(entry.hour_local);
    if (!Number.isInteger(hour) || hour < 0 || hour > 23 || seen.has(hour)) throw new Error("Jam jadwal harus unik dari 0 sampai 23.");
    seen.add(hour);
    if (typeof entry.enabled !== "boolean") throw new Error(`Status slot jam ${hour} tidak valid.`);
    const enabled = entry.enabled;
    const bossId = normalizeBossId(entry.boss_id, enabled);
    const bossName = normalizeBossName(entry.boss_name, enabled);
    const difficulty = normalizeDifficulty(entry.difficulty ?? "normal");
    const hpMultiplier = normalizeHpMultiplier(entry.hp_multiplier ?? 1);
    const spawnMinutes = normalizeDuration(entry.spawn_minutes ?? 60, 1, 60);
    const rewardConfig = parseBossReward(entry.reward_config ?? {});
    return {
      hour_local: hour, enabled, boss_id: bossId, boss_name: bossName,
      difficulty, hp_multiplier: hpMultiplier, spawn_minutes: spawnMinutes,
      reward_config: rewardConfig,
    };
  }).sort((a, b) => Number(a.hour_local) - Number(b.hour_local));
}
async function getCaveBossAdmin() {
  const [hours, override, logs, activeResult] = await Promise.all([
    requireData<any[]>(service.from("game_cave_boss_hourly_schedule").select("*").order("hour_local", { ascending: true })),
    requireData<any>(service.from("game_cave_boss_override").select("*").eq("id", true).maybeSingle()),
    requireData<any[]>(service.from("game_cave_boss_admin_log").select("log_id, admin_user_id, action, reason, details, created_at").order("created_at", { ascending: false }).limit(30)),
    service.rpc("get_active_cave_boss"),
  ]);
  if (activeResult.error) {
    console.error("get_active_cave_boss failed:", activeResult.error.message);
    throw Object.assign(new Error("RPC Boss Gua belum tersedia. Jalankan migrasi v16 dan periksa izin fungsi get_active_cave_boss."), { status: 503 });
  }
  return { hours, override, logs, active_boss: activeResult.data };
}
async function saveCaveBossSchedule(adminId: string, body: Record<string, unknown>) {
  const reason = cleanText(body.reason, 4, 500, "Alasan perubahan jadwal Boss");
  const hours = normalizeBossHours(body.hours);
  const saved = await requireData<any>(service.rpc("admin_save_cave_boss_hourly_schedule", {
    p_hours: hours, p_admin_user_id: adminId, p_reason: reason,
  }));
  const broadcastSent = await publishRealtimeBroadcast("cave-boss", "cave_boss_updated", {
    resource: "hourly_schedule", updated_at: new Date().toISOString(),
  });
  return { hours: saved, realtime: { broadcast_sent: broadcastSent, postgres_changes_enabled: true } };
}
async function triggerCaveBossNow(adminId: string, body: Record<string, unknown>) {
  const bossId = normalizeBossId(body.boss_id, true);
  const bossName = normalizeBossName(body.boss_name, true);
  const difficulty = normalizeDifficulty(body.difficulty ?? "normal");
  const hpMultiplier = normalizeHpMultiplier(body.hp_multiplier ?? 1);
  const duration = normalizeDuration(body.duration_minutes, 1, 180);
  const rewards = parseBossReward(body.reward_config ?? {});
  const reason = cleanText(body.reason, 4, 500, "Alasan pemanggilan Boss");
  const override = await requireData<any>(service.rpc("admin_set_cave_boss_override", {
    p_boss_id: bossId,
    p_boss_name: bossName,
    p_difficulty: difficulty,
    p_hp_multiplier: hpMultiplier,
    p_duration_minutes: duration,
    p_reward_config: rewards,
    p_admin_user_id: adminId,
    p_reason: reason,
  }));
  const broadcastSent = await publishRealtimeBroadcast("cave-boss", "cave_boss_updated", {
    resource: "manual_override", updated_at: new Date().toISOString(),
  });
  return { override, realtime: { broadcast_sent: broadcastSent, postgres_changes_enabled: true } };
}


async function getEventStoreAdmin() {
  const [config, items, logs] = await Promise.all([
    requireData<any>(service.from("game_event_store_config").select("*").eq("id", true).maybeSingle()),
    requireData<any[]>(service.from("game_event_store_items").select("*").order("sort_order", { ascending: true }).order("item_key", { ascending: true })),
    requireData<any[]>(service.from("game_event_store_admin_log").select("log_id, admin_user_id, action, reason, details, created_at").order("created_at", { ascending: false }).limit(30)),
  ]);
  return { config: config ?? null, items, logs };
}

async function saveEventStore(adminId: string, body: Record<string, unknown>) {
  const reason = cleanText(body.reason, 4, 500, "Alasan perubahan Event Shop");
  if (!isObject(body.config)) throw new Error("Konfigurasi Event Shop tidak valid.");
  if (!Array.isArray(body.items) || body.items.length > 100) throw new Error("Daftar item harus berupa array maksimal 100 item.");
  const config = body.config as Record<string, unknown>;
  const items = body.items.map((rawItem, index) => {
    if (!isObject(rawItem)) throw new Error(`Item #${index + 1} tidak valid.`);
    const itemKey = cleanText(rawItem.item_key, 1, 64, `Kunci item #${index + 1}`);
    if (!/^[A-Za-z0-9_-]+$/.test(itemKey)) throw new Error(`Kunci item #${index + 1} tidak valid.`);
    cleanText(rawItem.item_name, 1, 80, `Nama item #${index + 1}`);
    const price = String(rawItem.price_eyes ?? "");
    if (!/^\d{1,10}$/.test(price) || BigInt(price) > 2147483647n) throw new Error(`Harga item #${index + 1} harus 0-2.147.483.647.`);
    const order = Number(rawItem.sort_order);
    if (!Number.isInteger(order) || order < 0 || order > 100000) throw new Error(`Urutan item #${index + 1} tidak valid.`);
    if (rawItem.native_item_id !== null && rawItem.native_item_id !== undefined) {
      const nativeId = Number(rawItem.native_item_id);
      if (!Number.isInteger(nativeId) || nativeId < -2147483648 || nativeId > 2147483647) throw new Error(`ID native item #${index + 1} tidak valid.`);
    }
    if (typeof rawItem.enabled !== "boolean") throw new Error(`Status item #${index + 1} tidak valid.`);
    return rawItem;
  });
  if (typeof config.enabled !== "boolean") throw new Error("Status Event Shop harus berupa boolean.");
  cleanText(config.title, 1, 80, "Judul event");
  cleanText(config.banner_text, 1, 160, "Teks banner");
  if (!["once", "daily", "weekly"].includes(String(config.recurrence))) throw new Error("Mode pengulangan tidak valid.");
  const refresh = Number(config.refresh_minutes);
  if (!Number.isInteger(refresh) || refresh < 1 || refresh > 1440) throw new Error("Refresh harus 1-1440 menit.");
  const saved = await requireData<any>(service.rpc("admin_save_event_store", {
    p_config: config, p_items: items, p_admin_user_id: adminId, p_reason: reason,
  }));
  // A single Broadcast invalidation prompts every online client to reload the
  // current store snapshot immediately instead of processing many row events.
  const broadcastSent = await publishRealtimeBroadcast("event-store", "event_store_updated", {
    updated_at: new Date().toISOString(),
    item_count: items.length,
  });
  return {
    ...(isObject(saved) ? saved : { result: saved }),
    realtime: { broadcast_sent: broadcastSent, postgres_changes_enabled: true },
  };
}

async function clearCaveBossOverride(adminId: string, body: Record<string, unknown>) {
  const reason = cleanText(body.reason, 4, 500, "Alasan menghentikan override Boss");
  const override = await requireData<any>(service.rpc("admin_clear_cave_boss_override", {
    p_admin_user_id: adminId, p_reason: reason,
  }));
  const broadcastSent = await publishRealtimeBroadcast("cave-boss", "cave_boss_updated", {
    resource: "override_cleared", updated_at: new Date().toISOString(),
  });
  return { override, realtime: { broadcast_sent: broadcastSent, postgres_changes_enabled: true } };
}


// ---------------- Direct-Google player directory (v17.13) ----------------
async function listGooglePlayers() {
  const perPage = 1000;
  const maxRows = 20000;
  const players: any[] = [];
  for (let start = 0; start < maxRows; start += perPage) {
    const batch = await requireData<any[]>(service.from("game_google_players")
      .select("player_uuid, player_id, google_sub, email, email_verified, google_name, avatar_url, nickname, profile_completed, game_avatar_id, region, created_at, updated_at, last_seen_at")
      .order("created_at", { ascending: false }).range(start, start + perPage - 1));
    players.push(...batch);
    if (batch.length < perPage) break;
  }
  // Query wallets in small batches so a large player directory cannot exceed
  // the PostgREST URL/query-string limit when using .in(...).
  const walletMap = new Map<string, any>();
  const nativeWalletMap = new Map<string, any>();
  for (let i = 0; i < players.length; i += 150) {
    const ids = players.slice(i, i + 150).map((p: any) => p.player_uuid);
    if (!ids.length) continue;
    const [wallets, nativeWallets] = await Promise.all([
      requireData<any[]>(service.from("game_google_player_economy")
        .select("player_uuid, coins, crystals, goblin_coins, meat, meat_last_regen_at, energy, stamina, player_level, player_xp, updated_at")
        .in("player_uuid", ids)),
      requireData<any[]>(service.from("game_google_player_native_wallets")
        .select("player_uuid, coins, crystals, goblin_coins, meat, client_observed_at, server_received_at")
        .in("player_uuid", ids)),
    ]);
    for (const wallet of wallets) walletMap.set(wallet.player_uuid, wallet);
    for (const wallet of nativeWallets) nativeWalletMap.set(wallet.player_uuid, wallet);
  }
  return {
    players: players.map((p: any) => ({
      ...p,
      economy: walletMap.get(p.player_uuid) ?? null,
      native_wallet: nativeWalletMap.get(p.player_uuid) ?? null,
    })),
    total: players.length,
    truncated: players.length >= maxRows,
  };
}

function validateRewardConfig(raw: unknown) {
  if (!isObject(raw)) throw new Error("Reward harus berupa objek JSON.");
  const allowed = new Set(["coins", "crystals", "goblin_coins", "meat"]);
  const reward: Record<string, number> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (!allowed.has(key)) throw new Error(`Jenis reward tidak didukung: ${key}`);
    const n = Number(value);
    if (!Number.isSafeInteger(n) || n < 0 || n > 2147483647) throw new Error(`${key} harus bilangan bulat 0–2.147.483.647.`);
    if (key === "meat" && n > 24) throw new Error("Reward daging maksimal 24.");
    reward[key] = n;
  }
  if (!Object.keys(reward).length || Object.values(reward).every((v) => v === 0)) {
    throw new Error("Isi minimal satu reward dengan jumlah lebih dari 0.");
  }
  return reward;
}

async function listRewardCodes() {
  return await requireData<any[]>(service.from("game_reward_codes")
    .select("code_id, code, reward_config, enabled, max_uses, uses_count, starts_at, expires_at, created_at")
    .order("created_at", { ascending: false }).limit(500));
}

async function createRewardCode(adminId: string, body: Record<string, unknown>) {
  const code = cleanText(body.code, 4, 40, "Kode hadiah").toUpperCase();
  if (!/^[A-Z0-9-]{4,40}$/.test(code)) throw new Error("Kode hanya boleh berisi huruf A-Z, angka, dan tanda hubung.");
  const rewards = validateRewardConfig(body.reward_config);
  const maxUses = Number(body.max_uses ?? 1);
  if (!Number.isInteger(maxUses) || maxUses < 1 || maxUses > 10000000) throw new Error("Batas klaim harus 1–10.000.000.");
  const reason = cleanText(body.reason, 4, 500, "Alasan pembuatan kode");
  const startsAt = body.starts_at ? new Date(String(body.starts_at)).toISOString() : null;
  const expiresAt = body.expires_at ? new Date(String(body.expires_at)).toISOString() : null;
  if (startsAt && expiresAt && new Date(expiresAt).getTime() <= new Date(startsAt).getTime()) throw new Error("Waktu kedaluwarsa harus setelah waktu mulai.");
  const row = await requireData<any>(service.from("game_reward_codes").insert({
    code, reward_config: rewards, max_uses: maxUses, starts_at: startsAt, expires_at: expiresAt,
    enabled: true, created_by: adminId,
  }).select("*").single());
  await requireData(service.from("game_reward_code_admin_log").insert({
    code_id: row.code_id, admin_user_id: adminId, action: "created", reason,
    details: { code, reward_config: rewards, max_uses: maxUses, starts_at: startsAt, expires_at: expiresAt },
  }));
  await recordAdminActivity(adminId, "Admin", "reward_code_created", null, { code, reward_config: rewards, max_uses: maxUses });
  return row;
}

async function setRewardCodeEnabled(adminId: string, body: Record<string, unknown>) {
  const codeId = uuid(body.code_id, "ID kode hadiah");
  if (typeof body.enabled !== "boolean") throw new Error("Status kode harus true/false.");
  const reason = cleanText(body.reason, 4, 500, "Alasan perubahan kode");
  const before = await requireData<any>(service.from("game_reward_codes").select("*").eq("code_id", codeId).single());
  const after = await requireData<any>(service.from("game_reward_codes").update({ enabled: body.enabled })
    .eq("code_id", codeId).select("*").single());
  await requireData(service.from("game_reward_code_admin_log").insert({
    code_id: codeId, admin_user_id: adminId, action: body.enabled ? "enabled" : "disabled", reason,
    details: { before_enabled: before.enabled, after_enabled: after.enabled },
  }));
  await recordAdminActivity(adminId, "Admin", body.enabled ? "reward_code_enabled" : "reward_code_disabled", null, { code: after.code });
  return after;
}


// Unified activity feed for the live admin dashboard.
async function listGoogleActivity() {
  const activities = await requireData<any[]>(service.from("game_google_activity")
    .select("activity_id,actor_type,player_uuid,admin_user_id,actor_email,action,details,created_at")
    .order("created_at", { ascending: false }).limit(300));
  const playerIds = [...new Set(activities.map((a: any) => a.player_uuid).filter(Boolean))];
  const playerMap = new Map<string, any>();
  for (let i = 0; i < playerIds.length; i += 150) {
    const batch = playerIds.slice(i, i + 150);
    if (!batch.length) continue;
    const players = await requireData<any[]>(service.from("game_google_players")
      .select("player_uuid,player_id,email,nickname,avatar_url,game_avatar_id").in("player_uuid", batch));
    for (const player of players) playerMap.set(player.player_uuid, player);
  }
  return { activities: activities.map((a: any) => ({ ...a, player: a.player_uuid ? playerMap.get(a.player_uuid) ?? null : null })) };
}

async function recordAdminActivity(
  adminId: string, adminEmail: string, action: string,
  playerUuid: string | null = null, details: Record<string, unknown> = {},
) {
  const { error } = await service.from("game_google_activity").insert({
    actor_type: "admin", player_uuid: playerUuid, admin_user_id: adminId,
    actor_email: adminEmail, action, details,
  });
  if (error) console.warn("Could not persist admin activity:", error.message);
}

// ---------------- In-game Surat mailbox (v17.14) ----------------
async function listPlayerMail() {
  return await requireData<any[]>(service.from("game_google_player_mail")
    .select("mail_id, player_uuid, recipient_email, subject, message, reward_config, admin_name, reason, created_at, expires_at, claimed_at")
    .order("created_at", { ascending: false }).limit(300));
}

async function sendPlayerMail(adminId: string, adminName: string, body: Record<string, unknown>) {
  const email = cleanText(body.recipient_email, 5, 254, "Email akun Google").toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("Email tujuan tidak valid.");
  const player = await requireData<any>(service.from("game_google_players")
    .select("player_uuid,email,email_verified,nickname,player_id").eq("email", email).maybeSingle());
  if (!player) throw new Error("Akun Google dengan email itu belum terdaftar sebagai pemain.");
  if (!player.email_verified) throw new Error("Email pemain belum terverifikasi Google.");
  const subject = cleanText(body.subject, 1, 100, "Judul surat");
  const message = cleanText(body.message, 1, 2000, "Isi surat");
  let rewards: Record<string, number> = {};
  if (body.reward_config !== undefined) {
    if (!isObject(body.reward_config)) throw new Error("Hadiah surat harus berupa objek.");
    const hasPositiveReward = Object.values(body.reward_config).some((v) => Number(v) > 0);
    rewards = hasPositiveReward ? validateRewardConfig(body.reward_config) : {};
  }
  const reason = cleanText(body.reason, 4, 500, "Alasan pengiriman surat");
  const expiresAt = body.expires_at ? new Date(String(body.expires_at)).toISOString() : null;
  if (expiresAt && new Date(expiresAt).getTime() <= Date.now()) throw new Error("Masa berlaku surat harus di masa depan.");
  const mail = await requireData<any>(service.from("game_google_player_mail").insert({
    player_uuid: player.player_uuid, recipient_email: email, subject, message,
    reward_config: rewards, created_by: adminId, admin_name: adminName || "Admin",
    reason, expires_at: expiresAt,
  }).select("mail_id,player_uuid,recipient_email,subject,message,reward_config,admin_name,reason,created_at,expires_at,claimed_at").single());
  await requireData(service.from("game_google_mail_admin_log").insert({
    mail_id: mail.mail_id, admin_user_id: adminId, action: "sent", reason,
    details: { player_id: player.player_id, nickname: player.nickname, recipient_email: email, reward_config: rewards },
  }));
  await recordAdminActivity(adminId, adminName || "Admin", "mail_sent", player.player_uuid, {
    mail_id: mail.mail_id, subject, recipient_email: email, reward_config: rewards,
  });
  const broadcastSent = await publishRealtimeBroadcast("google-admin-dashboard", "google_player_changed", {
    player_uuid: player.player_uuid, resource: "mail_sent", updated_at: new Date().toISOString(),
  });
  await publishRealtimeBroadcast(`google-player-${player.player_uuid}`, "mail_received", { mail_id: mail.mail_id });
  return { mail, player: { player_uuid: player.player_uuid, player_id: player.player_id, nickname: player.nickname },
    wallet_credited: false, realtime: { broadcast_sent: broadcastSent } };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return fail("Gunakan POST.", 405);
  try {
    const body = await request.json().catch(() => null);
    if (!isObject(body)) return fail("Body JSON tidak valid.");
    const { user, admin } = await requireAdmin(request, body);
    const action = body.action;
    let result: unknown;
    if (action === "list_google_players") result = await listGooglePlayers();
    else if (action === "list_reward_codes") result = await listRewardCodes();
    else if (action === "list_player_mail") result = await listPlayerMail();
    else if (action === "list_google_activity") result = await listGoogleActivity();
    else if (action === "send_player_mail") result = await sendPlayerMail(user.id, String(user.email ?? "Admin"), body);
    else if (action === "create_reward_code") result = await createRewardCode(user.id, body);
    else if (action === "set_reward_code_enabled") result = await setRewardCodeEnabled(user.id, body);
    else if (action === "get_cave_boss_admin") result = await getCaveBossAdmin();
    else if (action === "save_cave_boss_schedule") result = await saveCaveBossSchedule(user.id, body);
    else if (action === "trigger_cave_boss_now") result = await triggerCaveBossNow(user.id, body);
    else if (action === "clear_cave_boss_override") result = await clearCaveBossOverride(user.id, body);
    else if (action === "get_event_store_admin") result = await getEventStoreAdmin();
    else if (action === "save_event_store") result = await saveEventStore(user.id, body);
    else if (action === "whoami") {
      result = { admin: { user_id: user.id, email: user.email ?? null, role: admin.role } };
    } else return fail("Aksi admin tidak dikenal.");
    if (["save_cave_boss_schedule", "trigger_cave_boss_now", "clear_cave_boss_override", "save_event_store"].includes(String(action))) {
      await recordAdminActivity(user.id, String(user.email ?? "Admin"), `admin_${String(action)}`, null, { completed: true });
    }
    return json({ ok: true, data: result });
  } catch (error) {
    const status = Number((error as { status?: number }).status ?? 400);
    const message = error instanceof Error ? error.message : "Permintaan gagal.";
    return fail(message, status >= 400 && status <= 599 ? status : 500);
  }
});
