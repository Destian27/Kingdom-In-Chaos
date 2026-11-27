from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
JAVA = ROOT / "dtp/src/com/destian/dtp/SupabaseGameBackend.java"
MAINT = ROOT / "dtp/src/com/destian/dtp/MaintenanceActivity.java"
SQL = ROOT / "supabase/game_online_v2.sql"
FOUNDATION = ROOT / "supabase/online-backend-foundation.sql"
EDGE = ROOT / "supabase/functions/game-online/index.ts"
README = ROOT / "README.md"


def test_backend_uses_same_public_supabase_project_key_as_maintenance():
    j = JAVA.read_text()
    m = MAINT.read_text()
    java_key = re.search(r'ANON_KEY\s*=\s*"([^"]+)"', j).group(1)
    maint_key = re.search(r'SUPABASE_ANON_KEY\s*=\s*"([^"]+)"', m).group(1)
    assert java_key == maint_key
    assert "service_role" not in java_key.lower()
    assert "service_role" not in j.lower() or "never put service_role" in j.lower()


def test_java_adapter_covers_requested_authenticated_functions():
    j = JAVA.read_text()
    for marker in (
        "getMyProfile(", "updateProfile(", "findPlayers(", "sendFriendRequest(",
        "getFriends(", "getFriendRequests(", "getRankings(",
        "getActiveWorldBossCycles(", "getWorldBossRankings(",
        "submitWorldBossScoreClaim(", "joinPvpQueue(", "getPvpHistory(",
        "saveGame(", "heartbeat(",
    ):
        assert marker in j, marker
    assert "signUp(" not in j and "signInWithPassword(" not in j


def test_sql_has_rls_rpc_and_server_only_competitive_result_writes():
    sql = SQL.read_text().lower()
    for marker in (
        "create or replace function public.send_game_friend_request",
        "create or replace function public.get_my_game_friends",
        "create or replace function public.join_game_pvp_queue",
        "create or replace function public.get_game_world_boss_rankings",
        "create or replace function public.submit_world_boss_score_claim",
        "create or replace function public.admin_approve_pvp_result",
        "create or replace function public.admin_approve_world_boss_claim",
        "revoke insert, update, delete on public.game_rankings from anon, authenticated",
        "grant execute on function public.admin_approve_pvp_result(uuid, uuid, jsonb) to service_role",
    ):
        assert marker in sql, marker


def test_operator_endpoint_requires_server_secret_and_does_not_live_in_apk_client():
    edge = EDGE.read_text()
    java = JAVA.read_text()
    assert "KIC_SCORE_REVIEW_KEY" in edge
    assert "SUPABASE_SERVICE_ROLE_KEY" in edge
    assert "x-kic-review-key" in edge
    assert "SUPABASE_SERVICE_ROLE_KEY" not in java
    assert "KIC_SCORE_REVIEW_KEY" not in java


def test_docs_disclose_native_bridge_limit():
    readme = README.read_text().lower()
    assert "not yet called by the original native game screens" in readme
    assert "native" in readme and "verifier" in readme


def test_java_online_hub_is_registered_and_reachable_from_game():
    manifest = (ROOT / "kingdom-in-chaos-decompiled/AndroidManifest.xml").read_text()
    app = (ROOT / "dtp/src/com/destian/dtp/DtpApp.java").read_text()
    overlay = (ROOT / "dtp/src/com/destian/dtp/GameOnlineOverlay.java").read_text()
    hub = (ROOT / "dtp/src/com/destian/dtp/GameOnlineHubActivity.java").read_text()
    assert 'android:name="com.destian.dtp.GameOnlineHubActivity"' in manifest
    assert 'android:exported="false"' in manifest.split('android:name="com.destian.dtp.GameOnlineHubActivity"')[0][-250:]
    assert "GameOnlineOverlay.install(a)" in app
    assert "GameOnlineHubActivity.class" in overlay
    assert "GooglePlayerBackend" in hub
    assert "Lanjutkan dengan Google" in hub
    assert "signUp(" not in hub and "signInWithPassword(" not in hub
    assert "native" in hub.lower() and "not" in hub.lower()
