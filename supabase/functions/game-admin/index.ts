import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAX_INT64 = 9223372036854775807n;
const BIGINT_FIELDS = new Set([
  "coins", "crystals", "goblin_coins", "event_eyes", "hero_xp", "player_xp", "energy",
  "stamina", "honor_points", "arena_tokens", "skill_points",
]);
const LEVEL_FIELDS = new Set(["hero_level", "player_level"]);
const ALLOWED_ECONOMY_FIELDS = new Set([...BIGINT_FIELDS, ...LEVEL_FIELDS, "extra_stats"]);

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

function safeAuthUser(user: Record<string, unknown>) {
  // Never return password hashes, login tokens, confirmation tokens, or raw auth records.
  return {
    id: user.id,
    email: user.email ?? null,
    email_confirmed_at: user.email_confirmed_at ?? null,
    phone: user.phone ?? null,
    phone_confirmed_at: user.phone_confirmed_at ?? null,
    created_at: user.created_at ?? null,
    updated_at: user.updated_at ?? null,
    last_sign_in_at: user.last_sign_in_at ?? null,
    banned_until: user.banned_until ?? null,
    confirmed_at: user.confirmed_at ?? null,
    is_anonymous: user.is_anonymous ?? false,
    user_metadata: user.user_metadata ?? {},
    app_metadata: user.app_metadata ?? {},
  };
}

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

async function requireAdmin(request: Request) {
  const header = request.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw Object.assign(new Error("Login Supabase diperlukan."), { status: 401 });
  const token = match[1];
  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !authData.user) {
    throw Object.assign(new Error("Sesi login tidak valid atau sudah kedaluwarsa."), { status: 401 });
  }
  const { data: adminRow, error: adminError } = await service
    .from("game_admin_users")
    .select("user_id, role, active")
    .eq("user_id", authData.user.id)
    .eq("active", true)
    .maybeSingle();
  if (adminError) throw Object.assign(new Error("Pemeriksaan hak admin gagal. Pastikan migrasi SQL sudah dijalankan."), { status: 503 });
  if (!adminRow) throw Object.assign(new Error("Akun ini belum diberi akses admin. Tambahkan akun melalui SQL bootstrap admin."), { status: 403 });
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

async function getRows(table: string, columns: string, ids: string[]) {
  if (!ids.length) return [];
  return await requireData<any[]>(service.from(table).select(columns).in("user_id", ids));
}

async function audit(adminId: string, targetId: string, action: string, reason: string,
  beforeData: Record<string, unknown>, afterData: Record<string, unknown>) {
  await requireData(service.from("game_admin_audit").insert({
    admin_user_id: adminId,
    target_user_id: targetId,
    action,
    reason,
    before_data: beforeData,
    after_data: afterData,
  }).select("audit_id").single());
}

async function listUsers(body: Record<string, unknown>) {
  const page = Math.max(1, Math.min(10000, Number.isInteger(body.page) ? Number(body.page) : 1));
  const perPage = 30;
  const q = typeof body.q === "string" ? body.q.trim().toLowerCase().slice(0, 100) : "";
  const { data, error } = await service.auth.admin.listUsers({ page, perPage });
  if (error) throw Object.assign(new Error("Tidak bisa mengambil daftar akun."), { status: 500 });
  const users: AdminAuthUser[] = (data.users ?? []) as AdminAuthUser[];
  const ids = users.map((u: AdminAuthUser) => u.id);
  const [profiles, presences, rankings, economies, saves] = await Promise.all([
    getRows("game_profiles", "user_id, legacy_uid, username, nickname, avatar_id, region, created_at, updated_at", ids),
    getRows("game_presence", "user_id, is_online, room_code, last_seen", ids),
    getRows("game_rankings", "user_id, level, total_score, pvp_wins, honor_points, updated_at", ids),
    getRows("game_admin_player_economy", "user_id, coins, crystals, goblin_coins, event_eyes, hero_xp, hero_level, player_xp, player_level, energy, stamina, honor_points, arena_tokens, skill_points, extra_stats, updated_at", ids),
    getRows("game_player_saves", "user_id, save_version, updated_at", ids),
  ]);
  const index = (rows: any[]) => new Map(rows.map((r) => [r.user_id, r]));
  const pMap = index(profiles), oMap = index(presences), rMap = index(rankings), eMap = index(economies), sMap = index(saves);
  type ListedUser = { auth_user: ReturnType<typeof safeAuthUser>; profile: any; presence: any; ranking: any; economy: any; save: any };
  let out: ListedUser[] = users.map((u: AdminAuthUser): ListedUser => ({
    auth_user: safeAuthUser(u as unknown as Record<string, unknown>),
    profile: pMap.get(u.id) ?? null,
    presence: oMap.get(u.id) ?? null,
    ranking: rMap.get(u.id) ?? null,
    economy: eMap.get(u.id) ?? null,
    save: sMap.get(u.id) ?? null,
  }));
  if (q) {
    out = out.filter((x: ListedUser) => [
      x.auth_user.email, x.auth_user.id, x.profile?.username, x.profile?.nickname,
    ].some((v) => String(v ?? "").toLowerCase().includes(q)));
  }
  return { users: out, page, per_page: perPage, has_more: (data.users?.length ?? 0) === perPage };
}

async function getUserDetail(targetId: string) {
  const [{ data: authResult, error: authError }, profile, presence, ranking, economy, save, history, audits] = await Promise.all([
    service.auth.admin.getUserById(targetId),
    requireData<any>(service.from("game_profiles").select("*").eq("user_id", targetId).maybeSingle()),
    requireData<any>(service.from("game_presence").select("*").eq("user_id", targetId).maybeSingle()),
    requireData<any>(service.from("game_rankings").select("*").eq("user_id", targetId).maybeSingle()),
    requireData<any>(service.from("game_admin_player_economy").select("*").eq("user_id", targetId).maybeSingle()),
    requireData<any>(service.from("game_player_saves").select("user_id, save_version, save_data, updated_at").eq("user_id", targetId).maybeSingle()),
    service.from("game_player_save_history").select("history_id, save_version, archived_at").eq("user_id", targetId).order("archived_at", { ascending: false }).limit(20),
    service.from("game_admin_audit").select("audit_id, admin_user_id, target_user_id, action, reason, before_data, after_data, created_at").eq("target_user_id", targetId).order("created_at", { ascending: false }).limit(50),
  ]);
  if (authError || !authResult.user) throw Object.assign(new Error("Akun tidak ditemukan."), { status: 404 });
  if (history.error && !history.error.message.includes("does not exist")) console.error("save history read failed", history.error.message);
  if (audits.error) console.error("audit read failed", audits.error.message);
  return {
    auth_user: safeAuthUser(authResult.user as unknown as Record<string, unknown>),
    profile, presence, ranking, economy, save,
    save_history: history.error ? [] : (history.data ?? []),
    audit: audits.error ? [] : (audits.data ?? []),
  };
}

function validateEconomyFields(raw: unknown): Record<string, unknown> {
  if (!isObject(raw)) throw new Error("Data statistik tidak valid.");
  const keys = Object.keys(raw);
  if (!keys.length) throw new Error("Pilih setidaknya satu nilai untuk diubah.");
  const fields: Record<string, unknown> = {};
  for (const key of keys) {
    if (!ALLOWED_ECONOMY_FIELDS.has(key)) throw new Error(`Field tidak diizinkan: ${key}`);
    const value = raw[key];
    if (BIGINT_FIELDS.has(key)) {
      const text = String(value ?? "").trim();
      if (!/^\d{1,19}$/.test(text) || BigInt(text) > MAX_INT64) throw new Error(`${key} harus bilangan bulat 0 sampai ${MAX_INT64}.`);
      fields[key] = text; // send decimal text; Postgres converts it to BIGINT without JS precision loss
    } else if (LEVEL_FIELDS.has(key)) {
      const n = Number(value);
      if (!Number.isInteger(n) || n < 1 || n > 1_000_000) throw new Error(`${key} harus bilangan bulat 1 sampai 1.000.000.`);
      fields[key] = n;
    } else {
      let obj = value;
      if (typeof value === "string") {
        try { obj = JSON.parse(value); } catch { throw new Error("extra_stats harus JSON yang valid."); }
      }
      if (!isObject(obj)) throw new Error("extra_stats harus berupa objek JSON.");
      if (JSON.stringify(obj).length > 16000) throw new Error("extra_stats maksimal 16 KB.");
      fields.extra_stats = obj;
    }
  }
  return fields;
}

async function updateEconomy(adminId: string, body: Record<string, unknown>) {
  const targetId = uuid(body.target_user_id);
  const reason = cleanText(body.reason, 4, 500, "Alasan perubahan");
  const fields = validateEconomyFields(body.fields);
  // The database RPC applies the economy patch and writes its audit record in one transaction.
  // Only this server function has the service_role credential; never call the RPC from a client.
  const after = await requireData<any>(service.rpc("admin_update_player_economy", {
    p_target_user_id: targetId,
    p_fields: fields,
    p_reason: reason,
    p_admin_user_id: adminId,
  }));
  const broadcastSent = await notifyPlayerStateChanged(targetId, "economy");
  return { economy: after, realtime: { broadcast_sent: broadcastSent, postgres_changes_enabled: true } };
}

async function updateProfile(adminId: string, body: Record<string, unknown>) {
  const targetId = uuid(body.target_user_id);
  const reason = cleanText(body.reason, 4, 500, "Alasan perubahan");
  if (!isObject(body.fields)) throw new Error("Data profil tidak valid.");
  const raw = body.fields as Record<string, unknown>;
  const fields: Record<string, unknown> = {};
  if (raw.username !== undefined) {
    const username = cleanText(raw.username, 3, 32, "Username").toLowerCase();
    if (!/^[a-z0-9_]+$/.test(username)) throw new Error("Username hanya boleh berisi huruf, angka, dan garis bawah.");
    fields.username = username;
  }
  if (raw.nickname !== undefined) fields.nickname = cleanText(raw.nickname, 1, 32, "Nickname");
  if (raw.avatar_id !== undefined) {
    const n = Number(raw.avatar_id);
    if (!Number.isInteger(n) || n < 0 || n > 1000000) throw new Error("Avatar ID tidak valid.");
    fields.avatar_id = n;
  }
  if (raw.region !== undefined) fields.region = cleanText(raw.region, 1, 16, "Region");
  if (!Object.keys(fields).length) throw new Error("Tidak ada field profil yang diubah.");
  const before = await requireData<any>(service.from("game_profiles").select("*").eq("user_id", targetId).maybeSingle());
  if (!before) throw new Error("Profil pemain tidak ditemukan.");
  const after = await requireData<any>(service.from("game_profiles").update({ ...fields, updated_at: new Date().toISOString() }).eq("user_id", targetId).select("*").single());
  if (fields.nickname !== undefined || fields.avatar_id !== undefined) {
    await requireData(service.from("game_rankings").update({
      ...(fields.nickname !== undefined ? { nickname: fields.nickname } : {}),
      ...(fields.avatar_id !== undefined ? { avatar_id: fields.avatar_id } : {}),
      updated_at: new Date().toISOString(),
    }).eq("user_id", targetId));
  }
  await audit(adminId, targetId, "profile_update", reason, before, after);
  const broadcastSent = await notifyPlayerStateChanged(targetId, "profile");
  return { profile: after, realtime: { broadcast_sent: broadcastSent, postgres_changes_enabled: true } };
}

async function updateSave(adminId: string, body: Record<string, unknown>) {
  const targetId = uuid(body.target_user_id);
  const reason = cleanText(body.reason, 4, 500, "Alasan perubahan");
  let saveData: unknown = body.save_data;
  if (typeof saveData === "string") {
    try { saveData = JSON.parse(saveData); } catch { throw new Error("Save JSON tidak valid."); }
  }
  if (!isObject(saveData)) throw new Error("Save data harus berupa objek JSON.");
  const encoded = JSON.stringify(saveData);
  if (encoded.length > 500000) throw new Error("Save JSON maksimal 500 KB.");
  const before = await requireData<any>(service.from("game_player_saves").select("user_id, save_version, updated_at, save_data").eq("user_id", targetId).maybeSingle());
  const version = Math.max(1, Number(before?.save_version ?? 0) + 1);
  const after = await requireData<any>(service.from("game_player_saves").upsert({
    user_id: targetId, save_version: version, save_data: saveData, updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" }).select("user_id, save_version, updated_at, save_data").single());
  // Avoid duplicating potentially large save contents in the audit log.
  await audit(adminId, targetId, "save_update", reason,
    { save_version: before?.save_version ?? null, bytes: before ? JSON.stringify(before.save_data).length : 0 },
    { save_version: after.save_version, bytes: encoded.length });
  const broadcastSent = await notifyPlayerStateChanged(targetId, "save");
  return { save: after, realtime: { broadcast_sent: broadcastSent, postgres_changes_enabled: true } };
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

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return fail("Gunakan POST.", 405);
  try {
    const { user, admin } = await requireAdmin(request);
    const body = await request.json().catch(() => null);
    if (!isObject(body)) return fail("Body JSON tidak valid.");
    const action = body.action;
    let result: unknown;
    if (action === "list_users") result = await listUsers(body);
    else if (action === "get_user") result = await getUserDetail(uuid(body.target_user_id));
    else if (action === "update_economy") result = await updateEconomy(user.id, body);
    else if (action === "update_profile") result = await updateProfile(user.id, body);
    else if (action === "update_save") result = await updateSave(user.id, body);
    else if (action === "get_cave_boss_admin") result = await getCaveBossAdmin();
    else if (action === "save_cave_boss_schedule") result = await saveCaveBossSchedule(user.id, body);
    else if (action === "trigger_cave_boss_now") result = await triggerCaveBossNow(user.id, body);
    else if (action === "clear_cave_boss_override") result = await clearCaveBossOverride(user.id, body);
    else if (action === "get_event_store_admin") result = await getEventStoreAdmin();
    else if (action === "save_event_store") result = await saveEventStore(user.id, body);
    else if (action === "list_audit") {
      const targetId = body.target_user_id ? uuid(body.target_user_id) : null;
      let query = service.from("game_admin_audit").select("audit_id, admin_user_id, target_user_id, action, reason, before_data, after_data, created_at").order("created_at", { ascending: false }).limit(100);
      if (targetId) query = query.eq("target_user_id", targetId);
      result = { audit: await requireData<any[]>(query) };
    } else if (action === "whoami") {
      result = { admin: { user_id: user.id, email: user.email ?? null, role: admin.role } };
    } else return fail("Aksi admin tidak dikenal.");
    return json({ ok: true, data: result });
  } catch (error) {
    const status = Number((error as { status?: number }).status ?? 400);
    const message = error instanceof Error ? error.message : "Permintaan gagal.";
    return fail(message, status >= 400 && status <= 599 ? status : 500);
  }
});
