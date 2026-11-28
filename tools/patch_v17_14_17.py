#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_v17_14_17.py - v17.14.17 "ADMIN SAMBUNG"

Menambal paket v17.14.16 supaya perintah admin (Boss Gua, Event Shop, kode hadiah,
Surat, maintenance) benar-benar tersambung ke game untuk pemain login Google langsung,
dan aktivitasnya tampil lengkap di panel admin.

Setiap penggantian memakai rep(): WAJIB cocok tepat N kali, kalau tidak skrip berhenti.
Jadi patch tidak diam-diam gagal.
"""
import os, re, shutil, sys

SRC = "/home/claude/w/kingdom-in-chaos-dtp-v17.14.16"
DST = "/home/claude/out/kingdom-in-chaos-dtp-v17.14.17"

if os.path.exists(DST):
    shutil.rmtree(DST)
os.makedirs(os.path.dirname(DST), exist_ok=True)
shutil.copytree(SRC, DST)


def read(rel):
    with open(os.path.join(DST, rel), encoding="utf-8") as f:
        return f.read()


def write(rel, text):
    path = os.path.join(DST, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def rep(text, old, new, count=1, label=""):
    found = text.count(old)
    if found != count:
        sys.exit(f"[GAGAL] {label or old[:60]!r}: ditemukan {found}x, diharapkan {count}x")
    return text.replace(old, new)


# ======================================================================================
# 1) SQL: wrapper Event Shop untuk pemain Google (tanpa auth.uid) + kolom event_eyes
# ======================================================================================
sql_all = read("kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.14.8.sql")
start = sql_all.index("create or replace function public.get_active_event_store()")
end = sql_all.index("$$;", start) + 3
orig_fn = sql_all[start:end]

fn = orig_fn
fn = rep(fn, "public.get_active_event_store()", "public.game_google_active_event_store(p_player_uuid uuid)", label="nama fungsi")
fn = rep(fn, "v_user uuid := auth.uid();", "v_user uuid := p_player_uuid; -- v17.14.17: pemain Google tidak punya auth.uid()", label="v_user")
fn = rep(fn, "raise exception 'Authentication required';", "raise exception 'Player required';", label="pesan error")
fn = rep(
    fn,
    "from public.game_admin_player_economy e where e.user_id = v_user;",
    "from public.game_google_player_economy e where e.player_uuid = v_user;",
    label="sumber event_eyes",
)

sql_new = f"""-- ============================================================================
-- Kingdom In Chaos DTP v17.14.17 - ADMIN SAMBUNG
-- Jalankan SEKALI di Supabase SQL Editor (aman diulang). Jalankan SEBELUM deploy function.
--
-- MASALAH YANG DIPERBAIKI:
--   Sejak login Google langsung (v17.13), pemain tidak punya sesi Supabase Auth.
--   get_active_event_store() memakai auth.uid() lalu menolak "Authentication required",
--   dan RPC itu memang dicabut dari anon. Akibatnya perintah admin untuk Event Shop
--   tidak pernah sampai ke game. Fungsi ini versi yang dipanggil Edge Function google-player
--   (service_role) dengan p_player_uuid yang sudah diverifikasi lewat token Google.
--   Isi logika jadwal/katalog disalin PERSIS dari get_active_event_store() v17.4.
-- ============================================================================
begin;

-- Saldo Event Eyes pemain Google (sebelumnya hanya ada di tabel ekonomi akun Supabase Auth lama).
alter table public.game_google_player_economy
  add column if not exists event_eyes bigint not null default 0 check (event_eyes >= 0);

{fn}

revoke all on function public.game_google_active_event_store(uuid) from public, anon, authenticated;
grant execute on function public.game_google_active_event_store(uuid) to service_role;

commit;

-- Cek cepat (jalankan manual): ganti UUID dengan player_uuid dari tabel game_google_players
-- select public.game_google_active_event_store((select player_uuid from public.game_google_players limit 1));
"""
SQL_NAME = "kingdom-in-chaos-dtp-SQL-v17_14_17-admin-sambung.sql"
write(SQL_NAME, sql_new)
write("supabase/" + SQL_NAME, sql_new)
write("supabase/migrations/202611280001_admin_sambung_v17_14_17.sql", sql_new)

# ======================================================================================
# 2) Edge Function google-player: aksi get_cave_boss + get_event_store (ringan, read-only)
# ======================================================================================
gp = read("kingdom-in-chaos-dtp-google-player-function-v17_14_16.ts")
gp = "// v17.14.17: tambah aksi get_cave_boss & get_event_store agar perintah admin (Boss Gua / Event Shop) sampai ke pemain login Google langsung.\n" + gp

gp_helpers = '''// ---------------- v17.14.17: jalur baca Boss Gua & Event Shop untuk pemain Google ----------------
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

'''
gp = rep(gp, "Deno.serve(async (request: Request) => {", gp_helpers + "Deno.serve(async (request: Request) => {", label="gp helpers")
gp = rep(gp, "    let data: unknown;\n\n    if (action === \"bootstrap\") {",
         "    let data: unknown;\n    // v17.14.17: aksi baca-saja tidak memperbarui last_seen / tidak membroadcast ke dashboard.\n    let readOnlyPoll = false;\n\n    if (action === \"bootstrap\") {",
         label="gp var readOnlyPoll")
gp = rep(
    gp,
    "    } else if (action === \"sync_native_wallet\") {\n      data = await syncNativeWallet(identity, body);\n    } else {",
    "    } else if (action === \"sync_native_wallet\") {\n      data = await syncNativeWallet(identity, body);\n"
    "    } else if (action === \"get_cave_boss\") {\n      data = await getCaveBossForPlayer(identity);\n      readOnlyPoll = true;\n"
    "    } else if (action === \"get_event_store\") {\n      data = await getEventStoreForPlayer(identity);\n      readOnlyPoll = true;\n    } else {",
    label="gp dispatcher",
)
gp = rep(gp, "    await notifyGoogleAdminDashboard(identity, action);\n    return json({ ok: true, data });",
         "    if (!readOnlyPoll) await notifyGoogleAdminDashboard(identity, action);\n    return json({ ok: true, data });", label="gp notify")
write("kingdom-in-chaos-dtp-google-player-function-v17_14_17.ts", gp)
write("supabase/functions/google-player/index.ts", gp)

# ======================================================================================
# 3) Edge Function game-admin: log perintah lengkap + broadcast + maintenance di feed
# ======================================================================================
ga = read("kingdom-in-chaos-dtp-game-admin-function-v17.14.8.ts")
ga = ga.replace(
    "// v17.14.8: tidak ada perubahan perilaku dibanding v17.14.2. Hadiah admin diklaim dari tombol Bakat -> Hub Online di game.\n",
    "// v17.14.8: tidak ada perubahan perilaku dibanding v17.14.2. Hadiah admin diklaim dari tombol Bakat -> Hub Online di game.\n"
    "// v17.14.17: log perintah admin lengkap (alasan + detail), broadcast ke dashboard, dan riwayat maintenance ikut tampil di feed aktivitas.\n",
    1,
)
if "v17.14.17" not in ga:
    ga = "// v17.14.17: log perintah admin lengkap, broadcast dashboard, riwayat maintenance di feed aktivitas.\n" + ga

old_list = ga[ga.index("async function listGoogleActivity() {"): ga.index("async function recordAdminActivity(")]
new_list = '''async function listGoogleActivity() {
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
  const rows: any[] = activities.map((a: any) => ({ ...a, player: a.player_uuid ? playerMap.get(a.player_uuid) ?? null : null }));

  // v17.14.17: perintah maintenance dikirim lewat Edge Function lain (maintenance-admin) dan tidak
  // masuk game_google_activity. Riwayatnya sudah dicatat di app_maintenance_log, jadi digabung di sini
  // (hanya dibaca) supaya SEMUA perintah admin terlihat dalam satu feed. Kalau tabel belum ada, abaikan.
  try {
    const { data: maint, error: maintError } = await service.from("app_maintenance_log")
      .select("id,created_at,is_active,title,message,end_at").order("created_at", { ascending: false }).limit(60);
    if (!maintError && Array.isArray(maint)) {
      for (const m of maint) {
        rows.push({
          activity_id: `maint-${m.id}`, actor_type: "admin", player_uuid: null, admin_user_id: null,
          actor_email: "Admin (maintenance)", action: m.is_active ? "maintenance_on" : "maintenance_off",
          details: { title: m.title ?? "", message: m.message ?? "", end_at: m.end_at ?? null },
          created_at: m.created_at, player: null,
        });
      }
    }
  } catch (e) { console.warn("Riwayat maintenance tidak dapat digabung:", (e as Error).message); }

  rows.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  return { activities: rows.slice(0, 300) };
}

'''
ga = ga.replace(old_list, new_list, 1)

helpers = '''// ---------------- v17.14.17: pencatatan perintah admin yang konsisten ----------------
// Perintah yang mengubah apa yang dilihat pemain di game. Dicatat dengan alasan + ringkasan,
// lalu dashboard diberi broadcast agar semua tab admin menampilkan aktivitasnya seketika.
const COMMAND_ACTIVITY_ACTIONS = new Set([
  "save_cave_boss_schedule", "trigger_cave_boss_now", "clear_cave_boss_override", "save_event_store",
]);
// Dua aksi ini sudah mencatat aktivitasnya sendiri; di sini hanya perlu broadcast.
const BROADCAST_ONLY_ACTIONS = new Set(["create_reward_code", "set_reward_code_enabled"]);

function describeAdminCommand(action: string, body: Record<string, unknown>): Record<string, unknown> {
  const details: Record<string, unknown> = {
    reason: typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "",
  };
  if (action === "save_cave_boss_schedule" && Array.isArray(body.hours)) {
    details.slot_aktif = (body.hours as unknown[]).filter((h) => isObject(h) && h.enabled === true).length;
    details.total_slot = (body.hours as unknown[]).length;
  } else if (action === "trigger_cave_boss_now") {
    details.boss_id = String(body.boss_id ?? "");
    details.boss_name = String(body.boss_name ?? "");
    details.difficulty = String(body.difficulty ?? "");
    details.hp_multiplier = Number(body.hp_multiplier ?? 1);
    details.duration_minutes = Number(body.duration_minutes ?? 0);
  } else if (action === "save_event_store") {
    const cfg = isObject(body.config) ? body.config : {};
    details.title = String(cfg.title ?? "").slice(0, 80);
    details.enabled = cfg.enabled === true;
    details.recurrence = String(cfg.recurrence ?? "");
    details.item_count = Array.isArray(body.items) ? (body.items as unknown[]).length : 0;
  }
  return details;
}

'''
ga = rep(ga, "Deno.serve(async (request: Request) => {", helpers + "Deno.serve(async (request: Request) => {", label="ga helpers")

old_tail = ga[ga.index('    if (["save_cave_boss_schedule", "trigger_cave_boss_now", "clear_cave_boss_override", "save_event_store"].includes(String(action))) {'):
              ga.index("    return json({ ok: true, data: result });")]
new_tail = '''    // v17.14.17: catat perintah dengan alasan/detail lengkap, lalu broadcast ke dashboard admin.
    // Kegagalan pencatatan/broadcast tidak boleh menggagalkan perintah yang sudah tersimpan.
    const actionName = String(action);
    if (COMMAND_ACTIVITY_ACTIONS.has(actionName)) {
      await recordAdminActivity(user.id, String(user.email ?? "Admin"), `admin_${actionName}`, null, describeAdminCommand(actionName, body));
    }
    if (COMMAND_ACTIVITY_ACTIONS.has(actionName) || BROADCAST_ONLY_ACTIONS.has(actionName)) {
      await publishRealtimeBroadcast("google-admin-dashboard", "google_player_changed", {
        resource: actionName, updated_at: new Date().toISOString(),
      });
    }
'''
ga = ga.replace(old_tail, new_tail, 1)
assert "describeAdminCommand(actionName, body)" in ga
write("kingdom-in-chaos-dtp-game-admin-function-v17_14_17.ts", ga)
write("supabase/functions/game-admin/index.ts", ga)

# ======================================================================================
# 4) admin.html: label Indonesia, detail terbaca, filter, refresh otomatis setelah perintah
# ======================================================================================
ad = read("admin.html")

ad = rep(
    ad,
    '''<p class="mini">Riwayat login/profil, klaim Surat, kode hadiah, pembelian daging, dan tindakan admin. Pembaruan instan memakai Broadcast dengan refresh berkala sebagai cadangan.</p>
      <div class="toolbar"><button class="ghost" id="btnGoogleActivityRefresh">Muat ulang aktivitas</button><span class="mini" id="googleActivityStatus">Belum dimuat.</span></div>''',
    '''<p class="mini">Riwayat login/profil, klaim Surat, kode hadiah, pembelian daging, serta SEMUA perintah admin (Surat, kode hadiah, Boss Gua, Event Shop, maintenance) lengkap dengan alasannya. Pembaruan instan memakai Broadcast dengan refresh berkala sebagai cadangan.</p>
      <div class="toolbar"><button class="ghost" id="btnGoogleActivityRefresh">Muat ulang aktivitas</button>
        <select id="activityActorFilter" aria-label="Filter pelaku"><option value="">Semua pelaku</option><option value="admin">Admin saja</option><option value="player">Pemain saja</option></select>
        <input id="activitySearch" type="search" placeholder="Cari email / pemain / aktivitas" aria-label="Cari aktivitas" style="max-width:240px">
        <span class="mini" id="googleActivityStatus">Belum dimuat.</span></div>''',
    label="kartu aktivitas",
)

old_load = ad[ad.index("async function loadGoogleActivity() {"): ad.index('admin$("btnGoogleActivityRefresh").onclick = loadGoogleActivity;')]
new_load = r'''// v17.14.17: label Indonesia untuk kode aktivitas. Kode yang belum terdaftar tetap tampil apa adanya.
const ACTIVITY_LABELS = {
  google_login: "Pemain login Google", profile_completed: "Pemain menyelesaikan pendaftaran",
  meat_purchased: "Pemain membeli daging", meat_consumed: "Pemain memakai daging",
  reward_code_claimed: "Pemain menukar kode hadiah", mail_claimed: "Pemain mengklaim Surat",
  native_wallet_observed: "Saldo game berubah (terpantau)",
  mail_sent: "Admin mengirim Surat", reward_code_created: "Admin membuat kode hadiah",
  reward_code_enabled: "Admin mengaktifkan kode hadiah", reward_code_disabled: "Admin menonaktifkan kode hadiah",
  admin_save_cave_boss_schedule: "Admin menyimpan jadwal Boss Gua", admin_trigger_cave_boss_now: "Admin memanggil Boss Gua sekarang",
  admin_clear_cave_boss_override: "Admin menghentikan override Boss Gua", admin_save_event_store: "Admin menyimpan Event Shop",
  maintenance_on: "Admin mengaktifkan maintenance", maintenance_off: "Admin menonaktifkan maintenance"
};
const DETAIL_LABELS = {
  reason: "Alasan", subject: "Judul", recipient_email: "Penerima", code: "Kode", max_uses: "Maks. klaim",
  coins: "Koin", crystals: "DM", goblin_coins: "Goblin", meat: "Daging", boss_id: "ID Boss", boss_name: "Nama Boss",
  difficulty: "Kesulitan", hp_multiplier: "Pengali HP", duration_minutes: "Durasi (menit)", slot_aktif: "Slot aktif",
  total_slot: "Total slot", title: "Judul", enabled: "Aktif", recurrence: "Pengulangan", item_count: "Jumlah item",
  message: "Pesan", end_at: "Selesai", mail_id: "ID Surat", source_action: "Sumber"
};
function formatActivityDetail(details) {
  if (!details || typeof details !== "object") return "-";
  const parts = [];
  const walk = (obj, prefix) => {
    for (const [k, v] of Object.entries(obj)) {
      if (v === "" || v === null || v === undefined || k === "completed") continue;
      if (v && typeof v === "object" && !Array.isArray(v)) { walk(v, prefix); continue; }
      let shown = Array.isArray(v) ? v.join(", ") : v === true ? "ya" : v === false ? "tidak" : String(v);
      if (k === "end_at") shown = formatDate(v);
      parts.push((DETAIL_LABELS[k] || k) + ": " + shown);
    }
  };
  walk(details, "");
  return parts.length ? parts.join(" • ") : "-";
}
let activityItemsCache = [];
function renderGoogleActivity() {
  const rows = admin$("googleActivityRows");
  const status = admin$("googleActivityStatus");
  if (!rows || !status) return;
  const actorFilter = (admin$("activityActorFilter") || {}).value || "";
  const needle = ((admin$("activitySearch") || {}).value || "").trim().toLowerCase();
  const items = activityItemsCache.filter(a => {
    if (actorFilter && a.actor_type !== actorFilter) return false;
    if (!needle) return true;
    const hay = [a.actor_email, a.player?.nickname, a.player?.player_id, a.action, ACTIVITY_LABELS[a.action], formatActivityDetail(a.details)].join(" ").toLowerCase();
    return hay.includes(needle);
  });
  status.textContent = `${items.length.toLocaleString("id-ID")} dari ${activityItemsCache.length.toLocaleString("id-ID")} aktivitas terbaru`;
  rows.innerHTML = items.length ? items.map(a => {
    const actor = a.actor_type === "admin" ? "Admin" : "Pemain";
    const who = a.player?.nickname || a.player?.player_id || "-";
    const label = ACTIVITY_LABELS[a.action] || a.action || "-";
    return `<tr><td>${escapeHtml(formatDate(a.created_at))}</td><td>${actor}</td><td>${escapeHtml(a.actor_email || "-")}</td><td>${escapeHtml(who)}</td><td title="${escapeHtml(a.action || "")}">${escapeHtml(label)}</td><td title="${escapeHtml(JSON.stringify(a.details || {}))}">${escapeHtml(formatActivityDetail(a.details))}</td></tr>`;
  }).join("") : `<tr><td colspan="6">${activityItemsCache.length ? "Tidak ada aktivitas yang cocok dengan filter." : "Belum ada aktivitas tercatat."}</td></tr>`;
}
async function loadGoogleActivity() {
  const rows = admin$("googleActivityRows");
  const status = admin$("googleActivityStatus");
  if (!rows || !status) return;
  status.textContent = "Memuat aktivitas...";
  try {
    const result = await gameAdminRequest("list_google_activity");
    activityItemsCache = Array.isArray(result.activities) ? result.activities : [];
    renderGoogleActivity();
  } catch (e) {
    status.textContent = e.message;
    rows.innerHTML = `<tr><td colspan="6">${escapeHtml(e.message)}</td></tr>`;
  }
}
// Perintah admin berhasil -> feed aktivitas ikut segar (cadangan bila broadcast terlewat).
const refreshActivityQuietly = () => { if (creds) loadGoogleActivity().catch(() => {}); };
admin$("activityActorFilter").onchange = renderGoogleActivity;
admin$("activitySearch").oninput = renderGoogleActivity;
'''
ad = ad.replace(old_load, new_load, 1)

# Refresh aktivitas setelah tiap perintah
ad = rep(ad, "    admin$(\"rewardCodeValue\").value = \"\"; admin$(\"rewardCodeReason\").value = \"\";\n    await loadRewardCodes();",
         "    admin$(\"rewardCodeValue\").value = \"\"; admin$(\"rewardCodeReason\").value = \"\";\n    await loadRewardCodes();\n    refreshActivityQuietly();", label="refresh create code")
ad = rep(ad, "reason:reason.trim()}); await loadRewardCodes(); }",
         "reason:reason.trim()}); await loadRewardCodes(); refreshActivityQuietly(); }", label="refresh toggle code")
ad = rep(ad, "    await Promise.all([loadPlayerMail(), loadGooglePlayers()]);\n  } catch (e) { status.textContent = e.message; }",
         "    await Promise.all([loadPlayerMail(), loadGooglePlayers()]);\n    refreshActivityQuietly();\n  } catch (e) { status.textContent = e.message; }", label="refresh mail")
n_boss = ad.count("    await loadCaveBossAdmin();\n  } catch (e) { showCaveBossStatus")
assert n_boss == 3, f"handler boss ditemukan {n_boss}x, diharapkan 3x"
ad = ad.replace("    await loadCaveBossAdmin();\n  } catch (e) { showCaveBossStatus",
                "    await loadCaveBossAdmin();\n    refreshActivityQuietly();\n  } catch (e) { showCaveBossStatus")
ad = rep(ad, "    await loadEventStoreAdmin();\n  } catch (e) { status.textContent = e.message; }",
         "    await loadEventStoreAdmin();\n    refreshActivityQuietly();\n  } catch (e) { status.textContent = e.message; }", label="refresh event store")
# Maintenance (Edge Function terpisah): segarkan feed hanya jika panel data sudah pernah dibuka.
ad = rep(ad, 'msg.style.color = "var(--ok)"; msg.textContent = "Tersimpan. Game membaca perubahan dalam sekitar 2 detik.";',
         'msg.style.color = "var(--ok)"; msg.textContent = "Tersimpan. Game membaca perubahan dalam sekitar 2 detik.";\n    if (typeof adminDashboardStarted !== "undefined" && adminDashboardStarted) refreshActivityQuietly();',
         label="refresh maintenance save")
ad = rep(ad, '(sign > 0 ? "Waktu ditambah " : "Waktu dikurangi ") + dur(t) + ". Game membaca perubahan dalam sekitar 2 detik.";',
         '(sign > 0 ? "Waktu ditambah " : "Waktu dikurangi ") + dur(t) + ". Game membaca perubahan dalam sekitar 2 detik.";\n    if (typeof adminDashboardStarted !== "undefined" && adminDashboardStarted) refreshActivityQuietly();',
         label="refresh maintenance shift")

# Teks pesan yang menyesatkan -> sesuai perilaku nyata
ad = rep(ad, "Gameplay akan mengikuti jadwal setelah versi game membaca RPC get_active_cave_boss().",
         "Game membaca jadwal ini dari server dalam kisaran 15 detik (login Google langsung).", label="teks boss jadwal")
ad = rep(ad, "Pastikan klien Mode Gua membaca RPC agar perubahan terlihat di dalam game.",
         "Game membaca override ini dari server dalam kisaran 15 detik.", label="teks boss override")
ad = rep(ad, "APK akan membaca status dan katalog server maksimal sekitar 15 detik setelah polling berjalan.",
         "Game membaca status dan katalog dari server dalam kisaran 10 detik.", label="teks event store")
write("admin.html", ad)
write("kingdom-in-chaos-dtp-admin-v17_14_17.html", ad)

# ======================================================================================
# 5) Java (sisi game)
# ======================================================================================
JD = "dtp/src/com/destian/dtp/"

# 5a) GooglePlayerBackend: dua metode baru
gb = read(JD + "GooglePlayerBackend.java")
gb = rep(
    gb,
    "    /** Claim a single mail item. The server atomically credits the wallet once. */",
    '''    /**
     * v17.14.17: Boss Gua aktif dari server. Login Google langsung tidak punya sesi Supabase Auth,
     * jadi SupabaseGameBackend.getActiveCaveBoss() tidak bisa dipakai; jalur ini lewat Edge Function.
     */
    public JSONObject getCaveBoss() throws IOException {
        return requestSavedAccount("get_cave_boss", new JSONObject());
    }

    /** v17.14.17: katalog + jadwal Event Shop dari server untuk pemain Google (termasuk saldo Event Eyes). */
    public JSONObject getEventStore() throws IOException {
        return requestSavedAccount("get_event_store", new JSONObject());
    }

    /** Claim a single mail item. The server atomically credits the wallet once. */''',
    label="GooglePlayerBackend metode",
)
write(JD + "GooglePlayerBackend.java", gb)

# 5b) DtpApp: fallback ke jalur Google bila tidak ada sesi Supabase
da = read(JD + "DtpApp.java")
da = rep(
    da,
    "    private static final long EVENT_STORE_POLL_MS = 1000L;\n",
    "    private static final long EVENT_STORE_POLL_MS = 1000L;\n"
    "    // v17.14.17: jalur Google memanggil Edge Function, jadi dibatasi agar poll 1 detik Event Shop\n"
    "    // tidak menjadi 1 request/detik ke server. Perubahan admin tetap terbaca dalam <= 10 detik.\n"
    "    private static final long GOOGLE_ADMIN_MIN_INTERVAL_MS = 10000L;\n"
    "    private volatile long googleCaveBossLastMs;\n"
    "    private volatile long googleEventStoreLastMs;\n",
    label="DtpApp konstanta",
)
da = rep(
    da,
    "                    if (backend.hasSession()) cacheCaveBossState(backend.getActiveCaveBoss());\n                } catch (Throwable ignored) {",
    "                    if (backend.hasSession()) {\n"
    "                        cacheCaveBossState(backend.getActiveCaveBoss());\n"
    "                    } else {\n"
    "                        // v17.14.17: pemain login Google langsung tidak punya sesi Supabase -> baca lewat Edge Function.\n"
    "                        // Tanpa ini perintah Boss Gua dari admin tidak pernah sampai ke game.\n"
    "                        GooglePlayerBackend google = new GooglePlayerBackend(getApplicationContext());\n"
    "                        long now = System.currentTimeMillis();\n"
    "                        if (google.hasAccount() && now - googleCaveBossLastMs >= GOOGLE_ADMIN_MIN_INTERVAL_MS) {\n"
    "                            googleCaveBossLastMs = now;\n"
    "                            cacheCaveBossState(google.getCaveBoss());\n"
    "                        }\n"
    "                    }\n"
    "                } catch (Throwable ignored) {",
    label="DtpApp boss fallback",
)
da = rep(
    da,
    "                    if (backend.hasSession()) cacheEventStoreState(backend.getActiveEventStore());\n                    else cacheEventStoreState(new JSONObject());",
    "                    if (backend.hasSession()) {\n"
    "                        cacheEventStoreState(backend.getActiveEventStore());\n"
    "                    } else {\n"
    "                        // v17.14.17: sebelumnya di sini cache dikosongkan ({}) sehingga Event Shop dari admin\n"
    "                        // tidak pernah tampil untuk pemain Google. Kini dibaca lewat Edge Function (dibatasi interval).\n"
    "                        GooglePlayerBackend google = new GooglePlayerBackend(getApplicationContext());\n"
    "                        long now = System.currentTimeMillis();\n"
    "                        if (google.hasAccount()) {\n"
    "                            if (now - googleEventStoreLastMs >= GOOGLE_ADMIN_MIN_INTERVAL_MS) {\n"
    "                                googleEventStoreLastMs = now;\n"
    "                                cacheEventStoreState(google.getEventStore());\n"
    "                            }\n"
    "                        } else {\n"
    "                            cacheEventStoreState(new JSONObject());\n"
    "                        }\n"
    "                    }",
    label="DtpApp event store fallback",
)
write(JD + "DtpApp.java", da)

# 5c) GameEventStoreActivity: layar Event Shop juga lewat jalur Google
ge = read(JD + "GameEventStoreActivity.java")
ge = rep(
    ge,
    '                    SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());\n'
    '                    if (!backend.hasSession()) throw new IllegalStateException("Login melalui tombol ONLINE di game terlebih dahulu.");\n'
    '                    final JSONObject state = backend.getActiveEventStore();',
    '                    SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());\n'
    '                    final JSONObject state;\n'
    '                    if (backend.hasSession()) {\n'
    '                        state = backend.getActiveEventStore();\n'
    '                    } else {\n'
    '                        // v17.14.17: pemain login Google langsung -> ambil katalog lewat Edge Function google-player.\n'
    '                        GooglePlayerBackend google = new GooglePlayerBackend(getApplicationContext());\n'
    '                        if (!google.hasAccount()) throw new IllegalStateException("Login melalui tombol ONLINE di game terlebih dahulu.");\n'
    '                        state = google.getEventStore();\n'
    '                    }',
    label="GameEventStoreActivity loadStore",
)
write(JD + "GameEventStoreActivity.java", ge)

# ======================================================================================
# 6) Dokumen + tes
# ======================================================================================
write("CHANGELOG-V17.14.17-ADMIN-SAMBUNG.md", '''# v17.14.17 - ADMIN SAMBUNG (perintah & aktivitas admin tersambung 100% ke game)

## Akar masalah
Sejak login Google langsung (v17.13) pemain **tidak punya sesi Supabase Auth**. Tetapi jalur game untuk
**Boss Gua** dan **Event Shop** masih memakai `SupabaseGameBackend.hasSession()`:
- Event Shop: tanpa sesi, cache diisi `{}` (kosong) -> katalog dari admin tidak pernah tampil.
- Boss Gua: tanpa sesi, tidak diambil sama sekali -> perintah "Panggil Boss Sekarang" / jadwal tidak sampai.
- RPC `get_active_event_store` memakai `auth.uid()` dan dicabut dari `anon`, jadi tidak bisa dipanggil tanpa sesi.

## Perbaikan
- SQL baru `kingdom-in-chaos-dtp-SQL-v17_14_17-admin-sambung.sql`: fungsi `game_google_active_event_store(p_player_uuid)`
  (logika jadwal/katalog disalin persis dari fungsi lama, hanya sumber identitas & saldo Event Eyes yang diganti) + kolom
  `event_eyes` di `game_google_player_economy`. Hanya `service_role` yang boleh menjalankannya.
- Edge Function `google-player` v17.14.17: aksi baca-saja `get_cave_boss` dan `get_event_store` (token Google diverifikasi
  seperti aksi lain). Aksi ini tidak menulis `last_seen`/broadcast, jadi polling tidak membanjiri dashboard admin.
- Java: `GooglePlayerBackend.getCaveBoss()/getEventStore()`; `DtpApp` (poll Boss & Event Shop) dan `GameEventStoreActivity`
  memakai jalur Google bila tidak ada sesi Supabase. Dibatasi 1 request / 10 detik per jenis.
- Edge Function `game-admin` v17.14.17: perintah Boss/Event Shop dicatat dengan **alasan + ringkasan**
  (sebelumnya hanya `completed: true`), semua perintah (termasuk kode hadiah) memicu broadcast dashboard, dan riwayat
  **maintenance** (dari `app_maintenance_log`) ikut tampil di feed aktivitas.
- `admin.html`: label aktivitas berbahasa Indonesia, detail terbaca, filter pelaku + pencarian, feed otomatis segar
  setelah setiap perintah (Surat, kode hadiah, Boss, Event Shop, maintenance). Teks status yang menyesatkan diperbaiki.

## Urutan pasang
1. SQL Editor Supabase: jalankan `kingdom-in-chaos-dtp-SQL-v17_14_17-admin-sambung.sql`.
2. Deploy `google-player` (`kingdom-in-chaos-dtp-google-player-function-v17_14_17.ts`) dan `game-admin`
   (`kingdom-in-chaos-dtp-game-admin-function-v17_14_17.ts`). `maintenance-admin` tidak berubah.
3. Upload `kingdom-in-chaos-dtp-admin-v17_14_17.html` ke hosting admin.
4. Build APK ulang dari paket ini (perubahan Java ikut).

## Yang belum / batas
- APK belum dibuild dan belum diuji di perangkat; edge function belum dideploy dari sini. Perubahan Java hanya diperiksa
  secara struktur teks.
- Saldo **Event Eyes** pemain Google dimulai 0 dan belum ada cara admin mengisinya (hadiah Surat/kode hanya mendukung
  coins, crystals, goblin_coins, meat). Perlu keputusan: tambah `event_eyes` ke hadiah Surat?
- Notifikasi instan "Surat baru" ke game belum ada: server sudah mengirim broadcast `mail_received`, tetapi game
  belum mendengarkannya. Surat muncul saat kotak surat dibuka.
- Aktivitas pemain yang tercatat tetap hanya: login, daftar, daging, kode, klaim Surat, perubahan saldo.
''')
write("VERSION-v17.14.17-ADMIN-SAMBUNG.txt", "v17.14.17 ADMIN SAMBUNG - Boss Gua & Event Shop kini terbaca game via login Google langsung; aktivitas admin lengkap.\n")

write("tests/test_v17_14_17_admin_sambung.py", '''"""v17.14.17 - pemeriksaan struktur teks (tanpa jaringan/APK)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")


def test_sql_wrapper_event_store_tanpa_auth_uid():
    sql = read("kingdom-in-chaos-dtp-SQL-v17_14_17-admin-sambung.sql")
    assert "game_google_active_event_store(p_player_uuid uuid)" in sql
    assert "v_user uuid := auth.uid()" not in sql
    assert "game_google_player_economy e where e.player_uuid = v_user" in sql
    assert "grant execute on function public.game_google_active_event_store(uuid) to service_role" in sql
    assert "to anon" not in sql and "to authenticated" not in sql


def test_google_player_aksi_baca_saja():
    ts = read("supabase/functions/google-player/index.ts")
    assert 'action === "get_cave_boss"' in ts and 'action === "get_event_store"' in ts
    assert "if (!readOnlyPoll) await notifyGoogleAdminDashboard" in ts
    assert ts == read("kingdom-in-chaos-dtp-google-player-function-v17_14_17.ts")


def test_game_admin_log_lengkap_dan_maintenance():
    ts = read("supabase/functions/game-admin/index.ts")
    assert "describeAdminCommand(actionName, body)" in ts
    assert "app_maintenance_log" in ts and "maintenance_on" in ts
    assert '{ completed: true }' not in ts
    assert ts == read("kingdom-in-chaos-dtp-game-admin-function-v17_14_17.ts")


def test_java_fallback_google():
    assert "getCaveBoss()" in read("dtp/src/com/destian/dtp/GooglePlayerBackend.java")
    app = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert "google.getCaveBoss()" in app and "google.getEventStore()" in app
    assert "cacheEventStoreState(new JSONObject());\\n                    }" not in app.split("refreshEventStoreAsync")[1][:900]
    assert "google.getEventStore()" in read("dtp/src/com/destian/dtp/GameEventStoreActivity.java")


def test_admin_html_label_filter_refresh():
    html = read("admin.html")
    assert "ACTIVITY_LABELS" in html and "activityActorFilter" in html
    assert html.count("refreshActivityQuietly()") >= 8
    assert html == read("kingdom-in-chaos-dtp-admin-v17_14_17.html")
''')
print("OK: patch v17.14.17 selesai ->", DST)
