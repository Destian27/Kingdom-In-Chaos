from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path): return (ROOT / path).read_text(encoding="utf-8")

def test_player_login_uses_direct_google_not_supabase_auth():
    auth = read("dtp/src/com/destian/dtp/GameAuthActivity.java")
    backend = read("dtp/src/com/destian/dtp/GooglePlayerBackend.java")
    assert "AccountManager.newChooseAccountIntent" in auth
    assert "loginWithGoogleAccount" in auth
    assert "GoogleAuthUtil" in backend
    assert "userinfo" in backend or "openidconnect.googleapis.com" in read("supabase/functions/google-player/index.ts")
    assert "email_verified" in read("supabase/functions/google-player/index.ts")
    assert "auth/v1/authorize" not in auth
    assert "auth/v1/token" not in auth
    assert "password" not in auth.lower() or "password game" in auth.lower()

def test_google_player_phase_two_has_nickname_and_server_player_id():
    activity = read("dtp/src/com/destian/dtp/GameProfileSetupActivity.java")
    edge = read("supabase/functions/google-player/index.ts")
    sql = read("supabase/migrations/202611270001_google_players_rewards_meat.sql")
    assert "Daftar" in activity
    assert "Nama Pengguna" in activity
    assert "player_id" in activity
    assert "complete_profile" in edge
    assert "profile_completed" in edge
    assert "player_id bigint generated always as identity" in sql


def test_admin_google_directory_and_reward_code_controls_exist():
    html = read("admin.html")
    edge = read("supabase/functions/game-admin/index.ts")
    assert "Semua Pemain — Google Auth" in html
    assert "googlePlayerRows" in html
    assert "Email Google" in html and "Avatar" in html
    assert "btnCreateRewardCode" in html and "Salin kode" in html
    assert 'action === "list_google_players"' in edge
    assert 'action === "create_reward_code"' in edge
    assert 'action === "set_reward_code_enabled"' in edge




def test_legacy_supabase_player_session_is_cleared_on_app_start():
    app = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert 'getSharedPreferences("kic_supabase_session_v1"' in app
    assert 'getSharedPreferences("kic_google_oauth_pending_v1"' in app
