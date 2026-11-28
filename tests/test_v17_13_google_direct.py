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




def test_version_and_build_output_are_17_14_2():
    yml = (ROOT / "kingdom-in-chaos-decompiled/apktool.yml").read_text()
    build = (ROOT / "build_dtp.py").read_text()
    assert "versionName: 17.14.8" in yml
    assert "versionCode: 16" in yml
    assert "KingdomInChaosDTP-v17.14.8-price-barter-crashfix.apk" in build


