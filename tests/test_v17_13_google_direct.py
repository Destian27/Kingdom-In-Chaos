from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def test_native_food_recovery_is_patched_to_five_minutes():
    import struct
    import zlib
    price = ROOT / "kingdom-in-chaos-decompiled/assets/public/config/price.xml"
    packed = price.read_bytes()
    xml = zlib.decompress(packed[4:])
    assert struct.unpack(">I", packed[:4])[0] == len(xml)
    assert b"<lifeRecoveryInterval>300</lifeRecoveryInterval>" in xml
    assert b"<buyLifeNum>12</buyLifeNum>" in xml
    assert b"<buyLifeCost>50</buyLifeCost>" in xml


def test_cloud_meat_is_explicitly_separate_from_native_food():
    src = (ROOT / "dtp/src/com/destian/dtp/GameMeatActivity.java").read_text()
    assert "cloud meat wallet" in src.lower()
    changelog = (ROOT / "CHANGELOG-V17.13-GOOGLE-DIRECT-REWARDS-MEAT.md").read_text()
    assert "Daging Cloud belum disinkronkan" in changelog


def test_version_and_build_output_are_17_14_2():
    yml = (ROOT / "kingdom-in-chaos-decompiled/apktool.yml").read_text()
    build = (ROOT / "build_dtp.py").read_text()
    assert "versionName: 17.14.2" in yml
    assert "versionCode: 12" in yml
    assert "KingdomInChaosDTP-v17.14.2-google-mail-crashfix.apk" in build


def test_google_profile_identity_refreshes_on_each_verified_request():
    source = (ROOT / "supabase/functions/google-player/index.ts").read_text()
    assert 'avatar_url: identity.picture' in source
    assert 'google_name: identity.name' in source
    assert 'email_verified: identity.email_verified' in source
    assert 'last_seen_at: now' in source
    assert 'google_player_changed' in source
    app = (ROOT / "dtp/src/com/destian/dtp/GameOnlineHubActivity.java").read_text()
    assert 'Foto profil Google disegarkan saat sinkronisasi akun' in app
