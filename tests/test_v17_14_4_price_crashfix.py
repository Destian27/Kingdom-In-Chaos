"""Tes regresi v17.14.4: price.xml tidak boleh punya elemen/atribut kosong."""
import re, struct, subprocess, sys, zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "kingdom-in-chaos-decompiled/assets/public/config"


def baca(nama):
    raw = (CONFIG / nama).read_bytes()
    xml = zlib.decompress(raw[4:])
    assert struct.unpack(">I", raw[:4])[0] == len(xml), nama + ": header panjang salah"
    return xml.decode("utf-8")


def test_semua_config_tanpa_elemen_atau_atribut_kosong():
    # Penyebab crash: node kosong -> DHValue null -> getValue() SIGSEGV 0x18.
    for f in CONFIG.glob("*.xml"):
        t = baca(f.name)
        assert not re.findall(r"<\w+\s*/>", t), f.name + " punya elemen kosong"
        assert not re.findall(r"\s\w+=\"\"", t), f.name + " punya atribut kosong"


def test_patch_price_idempotent_dan_barter_pindah_ke_json():
    before = (CONFIG / "price.xml").read_bytes()
    subprocess.check_call([sys.executable, str(ROOT / "tools/patch_price_dollar_fix.py")])
    assert (CONFIG / "price.xml").read_bytes() == before
    # v17.14.8: <barter> tidak boleh ada di price.xml (GetText() NULL -> SIGSEGV).
    assert "<barter" not in baca("price.xml")
    assert (ROOT / "kingdom-in-chaos-decompiled/assets/dtp_barter_prices.json").is_file()
    assert "<lifeRecoveryInterval>300</lifeRecoveryInterval>" in baca("price.xml")


def test_build_memanggil_patch_price():
    build = (ROOT / "build_dtp.py").read_text(encoding="utf8")
    assert "patch_price_dollar_fix()" in build
