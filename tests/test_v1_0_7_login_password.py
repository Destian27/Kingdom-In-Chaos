"""v1.0.7 - login Nama Pengguna + Kata Sandi, Google dihapus total (pemeriksaan struktur teks)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")
SRC = "dtp/src/com/destian/dtp/"


def test_google_classes_removed_and_manifest_clean():
    assert not (ROOT / SRC / "GoogleAccountPickerActivity.java").exists()
    assert not (ROOT / SRC / "GameProfileSetupActivity.java").exists()
    assert not (ROOT / SRC / "GooglePlayerBackend.java").exists()
    manifest = read("kingdom-in-chaos-decompiled/AndroidManifest.xml")
    for gone in ("GoogleAccountPicker", "GameProfileSetup", "GET_ACCOUNTS", "USE_CREDENTIALS"):
        assert gone not in manifest
    assert 'GameAuthActivity' not in manifest  # v1.0.8: dialog bawaan game dipakai


def test_java_sources_have_no_google_sign_in_code():
    for f in (ROOT / SRC).glob("*.java"):
        text = f.read_text(encoding="utf-8")
        for banned in ("GoogleAuthUtil", "oauth2:openid", "AccountManager", "beginGoogleOAuth", "chooseGoogleAccount"):
            assert banned not in text, (f.name, banned)


def test_auth_via_local_bridge_has_login_and_register():
    srv = read(SRC + "LocalAuthServer.java")
    assert "backend.register(user, pass)" in srv and "backend.login(user, pass)" in srv


def test_backend_stores_only_session_token_never_password():
    backend = read(SRC + "PlayerBackend.java")
    assert 'KEY_TOKEN' in backend and 'putString(KEY_TOKEN, token)' in backend
    assert backend.count('"password"') == 1  # hanya dikirim saat daftar/masuk, tidak disimpan
    assert "putString(\"password\"" not in backend


def test_server_function_password_login_and_session_token():
    ts = read("supabase/functions/google-player/index.ts")
    assert ts == read("kingdom-in-chaos-dtp-player-function-v1_0_9.ts")
    for needed in ('action === "register" || action === "login"', "verifySession(request)", "issueSessionToken",
                   "PBKDF2", "MAX_FAILED_LOGINS", "failed_attempts", 'google_sub: `local:${uid}`'):
        assert needed in ts, needed
    for banned in ("googleapis.com", "GOOGLE_WEB_OAUTH_CLIENT_ID", "tokeninfo", "userinfo"):
        assert banned not in ts, banned


def test_sql_adds_lock_columns_and_version():
    sql = read("kingdom-in-chaos-dtp-SQL-v1_0_7-login-password.sql")
    assert "failed_attempts" in sql and "locked_until" in sql and "game_google_player_credentials" in sql
    yml = read("kingdom-in-chaos-decompiled/apktool.yml")
    assert "versionName: 1.0.9" in yml and "versionCode: 109" in yml
