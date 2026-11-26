from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_google_oauth_pkce_and_encrypted_supabase_session():
    backend = (ROOT / "dtp/src/com/destian/dtp/SupabaseGameBackend.java").read_text()
    assert 'GOOGLE_REDIRECT_URI = "kingdominchaosdtp://auth"' in backend
    assert 'appendQueryParameter("provider", "google")' in backend
    assert 'appendQueryParameter("code_challenge_method", "s256")' in backend
    assert '"/auth/v1/token?grant_type=pkce"' in backend
    assert 'storeSession(result)' in backend
    assert "writeSecret(" in backend and "AndroidKeyStore" in backend


def test_auth_activity_and_deep_link_registered():
    manifest = (ROOT / "kingdom-in-chaos-decompiled/AndroidManifest.xml").read_text()
    auth = (ROOT / "dtp/src/com/destian/dtp/GameAuthActivity.java").read_text()
    assert 'android:name="com.destian.dtp.GameAuthActivity"' in manifest
    assert 'android:scheme="kingdominchaosdtp" android:host="auth"' in manifest
    assert "Login ke Kingdom In Chaos DTP" in auth
    assert 'getIdentifier("icon", "drawable"' in auth
    assert "completeGoogleOAuth(code, returnedState)" in auth


def test_game_overlay_has_login_entry_and_hub_gates_online_actions():
    overlay = (ROOT / "dtp/src/com/destian/dtp/GameOnlineOverlay.java").read_text()
    hub = (ROOT / "dtp/src/com/destian/dtp/GameOnlineHubActivity.java").read_text()
    assert "GameAuthActivity.class" in overlay
    assert "GameOnlineHubActivity.class" in overlay
    assert "backend.hasSession()" in hub
    assert "Login diperlukan untuk fitur ini" in hub
