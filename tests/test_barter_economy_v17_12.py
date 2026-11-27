from pathlib import Path
import importlib.util
import re
import struct
import zlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def read_text(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def unpack_config(relative):
    packed = (ROOT / relative).read_bytes()
    assert len(packed) > 6
    raw = zlib.decompress(packed[4:])
    assert struct.unpack(">I", packed[:4])[0] == len(raw)
    return ET.fromstring(raw)


def test_cash_payment_routes_are_disabled_in_both_arm_libraries():
    for abi in ("armeabi", "armeabi-v7a"):
        data = (ROOT / "kingdom-in-chaos-decompiled/lib" / abi / "libgame.so").read_bytes()
        assert data[0x2B98FC:0x2B9904] == bytes.fromhex("70 47 00 bf 00 bf 00 bf")
        assert data[0x2BD298:0x2BD29C] == bytes.fromhex("00 bf 00 bf")
        assert data[0x2BD416:0x2BD41A] == bytes.fromhex("00 bf 00 bf")
        # BL from onPaidOK now targets UIPopupManager::toastBuySuccess at 0x2dcdf0.
        assert data[0x2BD41E:0x2BD422] == bytes.fromhex("1f f0 e7 fc")


def test_packed_price_config_has_no_cash_values_and_has_barter_prices():
    root = unpack_config("kingdom-in-chaos-decompiled/assets/public/config/price.xml")
    cn = root.find("./dollar/cn")
    # v17.14.4: elemen kosong / sign kosong menyebabkan SIGSEGV DHValue::getValue
    # saat game dibuka, jadi sekarang node harus punya isi "0" (bukan uang nyata).
    assert cn is not None and cn.get("sign") == "Rp"
    assert all(child.text == "0" and not child.attrib for child in list(cn))
    barter = root.find("barter")
    assert barter is not None and barter.get("currency_exchange_rate") == "50_coin_per_dm"
    expected = {
        "vip30Days": ("coin", "30000"),
        "luckSpree": ("coin", "3500"),
        "newbieValue": ("dm", "299"),
        "newbieRich": ("dm", "999"),
        "equipmentItem": ("dm", "499"),
        "heroBundle": ("dm", "560"),
        "gearBundle": ("dm", "420"),
        "weeklyBundle": ("dm", "599"),
        "pvpTicket": ("dm", "99"),
        "seasonalA": ("dm", "499"),
        "seasonalB": ("dm", "1499"),
    }
    for name, (currency, cost) in expected.items():
        entry = barter.find(name)
        assert entry is not None
        assert entry.get("currency") == currency
        assert entry.get("cost") == cost


def test_native_bridge_deducts_balance_before_original_game_reward():
    cpp = read_text("dtp/native/game_runtime_bridge.cpp")
    assert "g_decreaseCoins(cost.amount, 6)" in cpp
    assert "g_decreaseCrystals(cost.amount, 6)" in cpp
    assert cpp.index("const bool paid = cost.usesCoins") < cpp.index("g_onPaidOK(priceManager, paymentId)")
    assert "paymentId >= 2 && paymentId <= 13" in cpp
    assert "paymentId >= 14 && paymentId <= 25" in cpp
    assert "doCurrencyExchange((paymentId - 2) % 3)" in cpp
    assert "doCurrencyExchange(3 + ((paymentId - 14) % 3))" in cpp
    assert "g_increaseCoins(reward, 6, true)" in cpp
    assert "g_increaseCrystals(reward, 6, true)" in cpp
    assert "g_crystalHookInstalled" in cpp
    # The direct barter JNI path returns the result to Java; it does not send a duplicate toast.
    method = cpp.split("Java_com_destian_dtp_NativeGameRuntimeBridge_performBarterNative", 1)[1]
    method = method.split("Java_com_destian_dtp_NativeGameRuntimeBridge_getWalletNative", 1)[0]
    assert "notifyBarter(" not in method


def test_overlay_shows_dm_progress_and_only_barter_price_labels():
    overlay = read_text("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "Total DM terkumpul" in overlay
    assert "2000L, 5000L, 15000L, 50000L" in overlay
    assert "VIP 30 hari  —  30.000 Koin" in overlay
    assert "Luck Spree  —  3.500 Koin" in overlay
    assert "Perlengkapan " in overlay and "499 DM" in overlay
    assert "Saldo akan dipotong sebelum hadiah diberikan" in overlay


def test_native_dm_counter_seeds_existing_balance_and_counts_new_crystals():
    java = read_text("dtp/src/com/destian/dtp/NativeGameRuntimeBridge.java")
    assert "seedLifetimeDmFromCurrentWallet()" in java
    assert "prefs.contains(KEY_DM_EARNED)" in java
    assert "putLong(KEY_DM_EARNED, next)" in java
    assert "onCrystalsEarned" in java


def test_build_script_patches_both_abis_and_compiles_thumb_bridge():
    build = read_text("build_dtp.py")
    patcher = read_text("tools/patch_barter_native.py")
    assert "patch_native_barter()" in build
    assert "patch_barter_native.py" in build
    assert '"-mthumb"' in build
    assert '"KingdomInChaosDTP-v17.14.6-wallet-crashfix.apk"' in build
    assert '"armeabi", "armeabi-v7a"' in patcher


def test_dollar_pack_strings_are_renamed_in_supported_game_locales():
    id_root = unpack_config("kingdom-in-chaos-decompiled/assets/public/config/string/id.xml")
    us_root = unpack_config("kingdom-in-chaos-decompiled/assets/public/config/string/us.xml")
    id_raw = zlib.decompress((ROOT / "kingdom-in-chaos-decompiled/assets/public/config/string/id.xml").read_bytes()[4:])
    us_raw = zlib.decompress((ROOT / "kingdom-in-chaos-decompiled/assets/public/config/string/us.xml").read_bytes()[4:])
    assert b"Paket Barter" in id_raw
    assert b"Dollar Pack" not in us_raw
