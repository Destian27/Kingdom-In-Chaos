from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def test_web_oauth_client_id_is_configured_and_id_tokens_are_verified():
    src = (ROOT / "supabase/functions/google-player/index.ts").read_text(encoding="utf-8")
    assert '"709171564273-tgg9tklkjsp02tovhganpdr3cqspnc2r.apps.googleusercontent.com"' in src
    assert 'GOOGLE_WEB_OAUTH_CLIENT_ID' in src
    assert 'tokeninfo' in src and 'searchParams.set("id_token", token)' in src
    assert 'String(claims.aud ?? "") !== GOOGLE_WEB_OAUTH_CLIENT_ID' in src
    assert 'email_verified' in src and 'expiry <= Math.floor(Date.now() / 1000)' in src

def test_android_access_token_uses_separate_android_oauth_client_id():
    src = (ROOT / "supabase/functions/google-player/index.ts").read_text(encoding="utf-8")
    assert 'GOOGLE_ANDROID_OAUTH_CLIENT_ID' in src
    assert 'searchParams.set("access_token", token)' in src
    assert 'issuedTo !== GOOGLE_ANDROID_OAUTH_CLIENT_ID' in src

def test_client_secret_is_not_embedded_in_source_or_client_files():
    src = (ROOT / "supabase/functions/google-player/index.ts").read_text(encoding="utf-8")
    java = (ROOT / "dtp/src/com/destian/dtp/GooglePlayerBackend.java").read_text(encoding="utf-8")
    assert "GOCSPX-" not in src
    assert "GOCSPX-" not in java
    assert "GOOGLE_OAUTH_CLIENT_SECRET" not in src
