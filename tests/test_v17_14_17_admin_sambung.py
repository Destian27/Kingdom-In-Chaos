"""v17.14.17 - pemeriksaan struktur teks (tanpa jaringan/APK)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")


def test_sql_wrapper_event_store_tanpa_auth_uid():
    sql_penuh = read("kingdom-in-chaos-dtp-SQL-GABUNGAN-v17_14_17.sql")
    sql = sql_penuh.split("BAGIAN 3: v17.14.17 ADMIN SAMBUNG")[1]  # hanya bagian baru
    assert "game_google_active_event_store(p_player_uuid uuid)" in sql
    assert "v_user uuid := auth.uid()" not in sql
    assert "game_google_player_economy e where e.player_uuid = v_user" in sql
    assert "grant execute on function public.game_google_active_event_store(uuid) to service_role" in sql
    assert "game_google_player_credentials" in sql_penuh and "BAGIAN 2" in sql_penuh


def test_google_player_aksi_baca_saja():
    ts = read("supabase/functions/google-player/index.ts")
    assert 'action === "get_cave_boss"' in ts and 'action === "get_event_store"' in ts
    assert "if (!readOnlyPoll) await notifyGoogleAdminDashboard" in ts
    assert ts == read("kingdom-in-chaos-dtp-google-player-function-v17_14_20.ts")


def test_game_admin_log_lengkap_dan_maintenance():
    ts = read("supabase/functions/game-admin/index.ts")
    assert "describeAdminCommand(actionName, body)" in ts
    assert "app_maintenance_log" in ts and "maintenance_on" in ts
    assert '{ completed: true }' not in ts
    assert ts == read("kingdom-in-chaos-dtp-game-admin-function-v17_14_20.ts")


def test_java_fallback_google():
    assert "getCaveBoss()" in read("dtp/src/com/destian/dtp/GooglePlayerBackend.java")
    app = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert "google.getCaveBoss()" in app and "google.getEventStore()" in app
    assert "cacheEventStoreState(new JSONObject());\n                    }" not in app.split("refreshEventStoreAsync")[1][:900]
    assert "google.getEventStore()" in read("dtp/src/com/destian/dtp/GameEventStoreActivity.java")


def test_admin_html_label_filter_refresh():
    html = read("admin.html")
    assert "ACTIVITY_LABELS" in html and "activityActorFilter" in html
    assert html.count("refreshActivityQuietly()") >= 8
    assert html == read("kingdom-in-chaos-dtp-admin-v17_14_20.html")
