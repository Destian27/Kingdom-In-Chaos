import os, struct, zlib, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEC = os.path.join(ROOT, "kingdom-in-chaos-decompiled")

def test_total_recharge_thresholds_in_dm():
    for abi in ("armeabi", "armeabi-v7a"):
        d = open(os.path.join(DEC, "lib", abi, "libgame.so"), "rb").read()
        got = tuple(struct.unpack_from("<f", d, o)[0] for o in (0x2BE208, 0x2BE20C, 0x2BE210, 0x2BE214))
        assert got == (40.0, 100.0, 300.0, 1000.0), (abi, got)

def test_life_functions_original_and_lifemax_kept():
    for abi in ("armeabi", "armeabi-v7a"):
        d = open(os.path.join(DEC, "lib", abi, "libgame.so"), "rb").read()
        assert d[0x3053A0:0x3053B2] == bytes.fromhex("f0b5474680b484b00f1c061cd9f7acff1b21")
        assert d[0x3055FC:0x305600] == bytes.fromhex("30b583b0")
        assert d[0x305330:0x305334] == bytes.fromhex("18 20 70 47")

def test_price_xml_dm_values():
    raw = open(os.path.join(DEC, "assets", "public", "config", "price.xml"), "rb").read()
    xml = zlib.decompress(raw[4:]).decode()
    assert '<cn sign="DM">' in xml and "<rookieGifts10>999<" in xml
