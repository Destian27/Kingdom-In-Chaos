"""v1.0.8 - Masuk/Daftar bawaan game lewat server lokal + Ganti Akun / Keluar."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")
SRC = "dtp/src/com/destian/dtp/"


def test_native_urls_patched_in_both_libs():
    for abi in ("armeabi-v7a", "armeabi"):
        data = (ROOT / "kingdom-in-chaos-decompiled/lib" / abi / "libgame.so").read_bytes()
        for new in (b"http://127.0.0.1:7391/%.0slogin?wifi=", b"http://127.0.0.1:7391/%.0ssignup?wifi=",
                    b"http://127.0.0.1:7391/%.0smo?uid=%d"):
            assert data.count(new) == 1, (abi, new)
        for old in (b"login_v16.php", b"signup_v16.php", b"modify.php"):
            assert old not in data


def test_patch_is_wired_into_build():
    assert "patch_local_auth()" in read("build_dtp.py")
    assert LocalPort() == 7391


def LocalPort():
    import re
    return int(re.search(r"PORT = (\d+)", read(SRC + "LocalAuthServer.java")).group(1))


def test_server_status_codes_match_native():
    srv = read(SRC + "LocalAuthServer.java")
    assert "status(-2" in srv and "status(0, null)" in srv and "NETWORK_ERROR = -9" in srv


def test_switch_and_logout():
    ov = read(SRC + "GameOnlineOverlay.java")
    assert "Ganti Akun" in ov and "Keluar" in ov
    ses = read(SRC + "AccountSession.java")
    for key in ("vsrrcvgl", "swapdrtg", "dwnxgldd", "ptmqpswf", "sjowkfzn", "hloomrqb"):
        assert key in ses
    assert "Cocos2dxPrefsFile" in ses and "clearAccountNow" in ses
    assert "LocalAuthServer.start" in read(SRC + "DtpApp.java")
    assert not (ROOT / SRC / "GameAuthActivity.java").exists()
