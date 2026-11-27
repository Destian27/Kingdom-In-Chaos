from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.3-ALL-IN-ONE.sql").read_text(encoding="utf-8")
TS = (ROOT / "supabase/functions/game-admin/index.ts").read_text(encoding="utf-8")
HTML = (ROOT / "admin.html").read_text(encoding="utf-8")


def test_event_shop_tables_are_realtime_readable_and_published():
    for table in ("game_event_store_config", "game_event_store_items"):
        assert f"grant select on public.{table} to authenticated;" in SQL
        assert f"create policy {table}_read_authenticated" in SQL
        assert f"'{table}'" in SQL
    assert "alter table public.%I replica identity full" in SQL
    assert "alter publication supabase_realtime add table public.%I" in SQL


def test_admin_edge_function_supports_event_shop_and_event_eyes():
    assert 'action === "get_event_store_admin"' in TS
    assert 'action === "save_event_store"' in TS
    assert "admin_save_event_store" in TS
    assert 'action === "update_economy"' not in TS
    assert 'action === "update_profile"' not in TS
    assert 'action === "update_save"' not in TS


def test_admin_html_uses_game_admin_edge_function_and_realtime_copy():
    assert '"/functions/v1/game-admin"' in HTML
    assert '"save_event_store"' in HTML
    assert "Semua Pemain — Google Auth" in HTML
    assert "Daftar otomatis dari akun Google terverifikasi" in HTML


def test_supabase_migration_versions_are_unique():
    migrations = sorted((ROOT / "supabase/migrations").glob("*.sql"))
    versions = [re.match(r"^(\d+)_", p.name).group(1) for p in migrations]
    assert len(versions) == len(set(versions))
    assert any(p.name == "202611260006_event_store_v17.sql" for p in migrations)


def test_realtime_android_subscriptions_have_unfiltered_event_store_channels():
    app = (ROOT / "dtp/src/com/destian/dtp/DtpApp.java").read_text(encoding="utf-8")
    activity = (ROOT / "dtp/src/com/destian/dtp/GameEventStoreActivity.java").read_text(encoding="utf-8")
    rt = (ROOT / "dtp/src/com/destian/dtp/RealtimeClient.java").read_text(encoding="utf-8")
    assert 'new String[] {"game_event_store_config", "game_event_store_items"}, null' in app
    assert 'new String[] {"game_event_store_config", "game_event_store_items"}, null' in activity
    assert '"realtime:event-store"' in app
    assert '"realtime:event-store"' in activity
    assert '"realtime:player-state-" + uid' in app
    assert '"broadcast".equals(ev)' in rt
    assert "channelTopic" in rt
    assert "loadAgain" in activity


def test_sql_transactions_are_balanced():
    begins = len(re.findall(r"^\s*begin\s*;", SQL, re.I | re.M))
    commits = len(re.findall(r"^\s*commit\s*;", SQL, re.I | re.M))
    assert begins == commits
    assert SQL.count("$$") % 2 == 0


def test_event_store_fallback_poll_is_one_second_and_sql_is_one_canonical_file():
    app = (ROOT / "dtp/src/com/destian/dtp/DtpApp.java").read_text(encoding="utf-8")
    activity = (ROOT / "dtp/src/com/destian/dtp/GameEventStoreActivity.java").read_text(encoding="utf-8")
    assert "EVENT_STORE_POLL_MS = 1000L" in app
    assert "EVENT_STORE_POLL_MS = 1000L" in activity
    assert "h.postDelayed(this, EVENT_STORE_POLL_MS)" in app
    assert "main.postDelayed(this, EVENT_STORE_POLL_MS)" in activity
    assert "15-second poll" not in (ROOT / "README-V17-EVENT-STORE.md").read_text(encoding="utf-8")
    canonical = ROOT / "kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.3-ALL-IN-ONE.sql"
    supabase_copy = ROOT / "supabase/kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.3-ALL-IN-ONE.sql"
    assert canonical.is_file() and supabase_copy.is_file()
    assert canonical.read_bytes() == supabase_copy.read_bytes()
    text = canonical.read_text(encoding="utf-8")
    for required in ("game_profiles", "game_maintenance_is_active", "game_cave_boss_hourly_schedule", "game_event_store_config", "game_event_store_items", "admin_save_event_store", "get_active_event_store"):
        assert required in text


def test_v173_edge_function_and_android_share_broadcast_topics():
    app = (ROOT / "dtp/src/com/destian/dtp/DtpApp.java").read_text(encoding="utf-8")
    activity = (ROOT / "dtp/src/com/destian/dtp/GameEventStoreActivity.java").read_text(encoding="utf-8")
    rt = (ROOT / "dtp/src/com/destian/dtp/RealtimeClient.java").read_text(encoding="utf-8")
    assert "const channel = service.channel(topic);" in TS
    assert 'publishRealtimeBroadcast("event-store", "event_store_updated"' in TS
    assert '`player-state-${targetId}`' in TS
    assert '"realtime:event-store"' in app and '"realtime:event-store"' in activity
    assert '"realtime:player-state-" + uid' in app
    assert '"event_store_updated".equals(broadcastEvent)' in rt
    assert '"player_state_updated".equals(broadcastEvent)' in rt
    assert '"cave_boss_updated".equals(broadcastEvent)' in rt
    assert '"realtime:cave-boss"' in app
    assert "stopCaveBossRealtime();" in app
    assert "game_admin_player_economy" in SQL
    assert "'game_player_saves'" in SQL
    assert (ROOT / "supabase/migrations/202611260007_player_event_realtime_v17_3.sql").is_file()
