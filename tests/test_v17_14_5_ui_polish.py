"""Tes regresi v17.14.5: teks tidak meluap, label tidak terpotong, bendera sesuai."""
import io, plistlib, re, struct, subprocess, sys, zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import patch_ui_polish as ui  # noqa: E402

CFG = ROOT / "kingdom-in-chaos-decompiled/assets/public/config/string"
PLIST = ROOT / "kingdom-in-chaos-decompiled/assets/release/plist"


def baca(n):
    return zlib.decompress((CFG / n).read_bytes()[4:]).decode("utf-8")


def test_baris_indonesia_tidak_melebihi_lebar_maksimum():
    xml = baca("de.xml")
    for m in ui.ITEM.finditer(xml):
        for line in m.group(2).split("\n"):
            assert len(line) <= ui.W_MAX or " " not in line, line


def test_deskripsi_skill_vampir_dipisah_seperti_inggris():
    assert "milikmu.\n(Waktu penggunaan ulang: %Ds)" in baca("de.xml")


def test_label_sempit_tidak_putus_di_tengah_kata():
    xml = baca("de.xml")
    assert '<i key="convert_skill">Skill</i>' in xml
    assert '<i key="convert_growthValueLerlevel">Pertumbuhan</i>' in xml
    assert "Ski\nll" not in xml and "Paket Dollar" not in xml


def test_slot_indonesia_memakai_bendera_indonesia_bukan_jerman():
    fr = plistlib.loads((PLIST / "nation.plist").read_bytes())["frames"]
    assert fr["UI/de.png"]["frame"] == fr["UI/id.png"]["frame"]


def test_nation_png_terenkripsi_roundtrip_dan_patch_idempotent():
    before = [(PLIST / n).read_bytes() for n in ("nation.png", "nation.plist")]
    png = ui.buka_png_terenkripsi(str(PLIST / "nation.png"))
    assert png[:8] == bytes.fromhex("89504e470d0a1a0a")
    subprocess.check_call([sys.executable, str(ROOT / "tools/patch_ui_polish.py")])
    assert before == [(PLIST / n).read_bytes() for n in ("nation.png", "nation.plist")]


def test_build_memanggil_patch_ui_polish():
    assert "patch_ui_polish()" in (ROOT / "build_dtp.py").read_text(encoding="utf8")
