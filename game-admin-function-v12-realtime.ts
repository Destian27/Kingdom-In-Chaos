import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAX_INT64 = 9223372036854775807n;
const BIGINT_FIELDS = new Set([
  "coins", "crystals", "goblin_coins", "hero_xp", "player_xp", "energy",
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
    throw Object.assign(new Error("Operasi database gagal. Pastikan SQL All-in-One v14 sudah dijalankan dan Edge Function sudah dideploy."), { status: 500 });
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
  let users = data.users ?? [];
  const ids = users.map((u) => u.id);
  const [profiles, presences, rankings, economies, saves] = await Promise.all([
    getRows("game_profiles", "user_id, legacy_uid, username, nickname, avatar_id, region, created_at, updated_at", ids),
    getRows("game_presence", "user_id, is_online, room_code, last_seen", ids),
    getRows("game_rankings", "user_id, level, total_score, pvp_wins, honor_points, updated_at", ids),
    getRows("game_admin_player_economy", "user_id, coins, crystals, goblin_coins, hero_xp, hero_level, player_xp, player_level, energy, stamina, honor_points, arena_tokens, skill_points, extra_stats, updated_at", ids),
    getRows("game_player_saves", "user_id, save_version, updated_at", ids),
  ]);
  const index = (rows: any[]) => new Map(rows.map((r) => [r.user_id, r]));
  const pMap = index(profiles), oMap = index(presences), rMap = index(rankings), eMap = index(economies), sMap = index(saves);
  let out = users.map((u) => ({
    auth_user: safeAuthUser(u as unknown as Record<string, unknown>),
    profile: pMap.get(u.id) ?? null,
    presence: oMap.get(u.id) ?? null,
    ranking: rMap.get(u.id) ?? null,
    economy: eMap.get(u.id) ?? null,
    save: sMap.get(u.id) ?? null,
  }));
  if (q) {
    out = out.filter((x) => [
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
  return { economy: after };
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
  return { profile: after };
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
  return { save: after };
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
