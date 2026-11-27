from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def read(p): return (ROOT / p).read_text(encoding="utf-8")

def test_avatar_box_hotspot_opens_google_first():
    s = read("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "return 2;" in s and "0.80f * h" in s

def test_register_screen_has_name_only_no_login_button():
    a = read("dtp/src/com/destian/dtp/GameProfileSetupActivity.java")
    assert "Nama Panggilan" in a and "ID Pemain" in a
    assert '"Masuk"' not in a and "password" not in a.lower()

def test_android_client_id_default_present():
    t = read("supabase/functions/google-player/index.ts")
    assert "709171564273-sk6tcg5nk2tk13lghb1hb4sc1he3c7me.apps.googleusercontent.com" in t
