from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def read(p): return (ROOT / p).read_text(encoding="utf-8")

def test_avatar_box_hotspot_opens_google_first():
    s = read("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "return 2;" in s and "0.80f * h" in s

def test_register_screen_has_username_password_verify():
    # v17.14.16: layar Daftar = Nama Pengguna + Kata Sandi (4-16) + Verifikasi Kata Sandi, tanpa tombol Masuk.
    a = read("dtp/src/com/destian/dtp/GameProfileSetupActivity.java")
    assert "Nama Pengguna" in a and "Kata Sandi" in a and "Verifikasi Kata Sandi" in a
    assert "Harus 4–16 karakter" in a and "TYPE_TEXT_VARIATION_PASSWORD" in a
    assert '"Masuk"' not in a
    b = read("dtp/src/com/destian/dtp/GooglePlayerBackend.java")
    assert "completeProfile(String nickname, String password)" in b

def test_server_hashes_password_never_plaintext():
    t = read("supabase/functions/google-player/index.ts")
    assert "PBKDF2" in t and "game_google_player_credentials" in t
    assert "password_hash" in t and "Kata sandi harus 4–16 karakter." in t
    sql = read("supabase/kingdom-in-chaos-dtp-SQL-v17_14_16-daftar-password.sql")
    assert "game_google_player_credentials" in sql and "revoke all" in sql

def test_google_player_gateway_jwt_disabled():
    assert "verify_jwt = false" in read("supabase/config.toml")

def test_android_client_id_default_present():
    t = read("supabase/functions/google-player/index.ts")
    assert "709171564273-sk6tcg5nk2tk13lghb1hb4sc1he3c7me.apps.googleusercontent.com" in t
