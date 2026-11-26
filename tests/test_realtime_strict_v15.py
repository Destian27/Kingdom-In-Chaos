from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def read(rel): return (ROOT / rel).read_text()

def test_maintenance_gate_fails_closed():
    s = read("dtp/src/com/destian/dtp/MaintenanceActivity.java")
    assert "BLOCK_WHEN_OFFLINE = true" in s
    assert "arr.length() != 1" in s
    assert "finishAndRemoveTask()" in s
    assert "public void onBackPressed()" in s

def test_running_game_kicks_on_unverified_status():
    s = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert "if (!r.ok)" in s and "kick(a);" in s
    assert "startPlayerStateRealtime(a)" in s
    assert "FLAG_NOT_TOUCHABLE" in s

def test_authenticated_player_realtime_tables():
    s = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert '"game_profiles", "game_player_saves", "game_admin_player_economy"' in s
    c = read("dtp/src/com/destian/dtp/RealtimeClient.java")
    assert "buildJoinMessage(String liveToken)" in c and 'change.put("filter", filter)' in c

def test_runtime_snapshot_method_and_hub_button():
    b = read("dtp/src/com/destian/dtp/SupabaseGameBackend.java")
    h = read("dtp/src/com/destian/dtp/GameOnlineHubActivity.java")
    assert "getMyRuntimeState()" in b
    assert "getAccessTokenForRealtime()" in b
    assert "Muat Snapshot Real-time" in h


def test_sql_enforces_maintenance_server_side():
    s = read("supabase/online-backend-super-complete-v15-realtime-strict.sql")
    assert "game_maintenance_is_active()" in s
    assert "guard_player_data_during_maintenance()" in s
    assert "GAME_IN_MAINTENANCE" in s
    assert "game_admin_player_economy_read_self" not in s  # the canonical economy policy name is checked below
    assert "game_admin_economy_read_self" in s


def test_player_realtime_refreshes_auth_token_on_reconnect_and_hub_auto_subscribes():
    c = read("dtp/src/com/destian/dtp/RealtimeClient.java")
    h = read("dtp/src/com/destian/dtp/GameOnlineHubActivity.java")
    assert "AccessTokenProvider" in c and "backend.currentUser()" in c
    assert "ensureRuntimeRealtimeSubscription()" in h
    assert "Realtime: data admin diperbarui" in h

def test_offline_gate_retries_but_stays_blocking():
    s = read("dtp/src/com/destian/dtp/MaintenanceActivity.java")
    assert "handler.postDelayed(tick, 1000)" in s
    assert "BLOCK_WHEN_OFFLINE = true" in s
    assert "Game tidak dapat dibuka" in s
