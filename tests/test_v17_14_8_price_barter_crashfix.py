"""Tes regresi v17.14.8: price.xml tanpa elemen tanpa teks; tombol overlay dihapus."""
import json
import pathlib
import re
import struct
import zlib
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_text(rel):
    return (ROOT / rel).read_text(encoding="utf8")


def test_price_xml_semua_saudara_dollar_punya_teks():
    raw = (ROOT / "kingdom-in-chaos-decompiled/assets/public/config/price.xml").read_bytes()
    assert struct.unpack(">I", raw[:4])[0] == len(zlib.decompress(raw[4:]))
    root = ET.fromstring(zlib.decompress(raw[4:]).decode("utf8"))
    for child in root:
        if child.tag == "dollar":
            continue
        assert len(child) == 0 and (child.text or "").strip(), child.tag


def test_data_barter_ada_di_json():
    data = json.loads(read_text("kingdom-in-chaos-decompiled/assets/dtp_barter_prices.json"))
    assert data["coinPack0"]["cost"] == "200" and data["seasonalB"]["cost"] == "1499"


def test_tombol_overlay_dihapus():
    overlay = read_text("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "removeLegacyButtons(root)" in overlay
    for name in ("addMailEntry", "addBarterEntry", 'setText("SURAT")', 'setText("BARTER")'):
        assert name not in overlay
    assert '"GOOGLE"' not in overlay


def test_layar_masuk_daftar_tanpa_google():
    srv = read_text("dtp/src/com/destian/dtp/LocalAuthServer.java")
    assert "chooseGoogleAccount" not in srv and "backend.login(user, pass)" in srv
    overlay = read_text("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "class Hotspots" not in overlay and "GameAuthActivity" not in overlay
    assert "promptGoogleLoginOnce" not in read_text("dtp/src/com/destian/dtp/DtpApp.java")


def test_versi_17_14_8():
    yml = read_text("kingdom-in-chaos-decompiled/apktool.yml")
    assert "versionName: 1.0.8" in yml and "versionCode: 108" in yml
    assert "KingdomInChaosDTP-v1.0.8.apk" in read_text("build_dtp.py")
