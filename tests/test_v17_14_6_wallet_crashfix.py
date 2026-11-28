"""Tes regresi v17.14.6: saldo native tidak boleh dibaca saat game baru dibuka tanpa pelindung."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_text(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_install_hooks_tidak_membaca_saldo_di_thread_ui():
    java = read_text("dtp/src/com/destian/dtp/NativeGameRuntimeBridge.java")
    body = java.split("public static String installEconomyHooks()", 1)[1]
    body = body.split("public static String performBarter", 1)[0]
    assert "seedLifetimeDm" not in body
    assert "getWalletNative" not in body


def test_seed_dm_malas_dari_getwallet_yang_berhasil():
    java = read_text("dtp/src/com/destian/dtp/NativeGameRuntimeBridge.java")
    body = java.split("public static String getWallet()", 1)[1].split("private static void seedLifetimeDmFromCurrentWallet", 1)[0]
    assert "seedLifetimeDmFromWallet(wallet)" in body
    assert 'wallet.startsWith("coins=")' in java  # hanya seed dari saldo valid
    assert "prefs.contains(KEY_DM_EARNED)" in java


def test_native_membaca_saldo_lewat_pelindung_sigsegv():
    cpp = read_text("dtp/native/game_runtime_bridge.cpp")
    assert "#include <setjmp.h>" in cpp and "#include <signal.h>" in cpp
    assert "sigsetjmp" in cpp and "siglongjmp" in cpp
    assert "bool runGuarded(" in cpp
    # Tiga JNI yang membaca LevelManager harus memakai pelindung.
    wallet = cpp.split("Java_com_destian_dtp_NativeGameRuntimeBridge_getWalletNative", 1)[1]
    assert "readWalletGuarded(&w)" in wallet
    apply_w = cpp.split("Java_com_destian_dtp_NativeGameRuntimeBridge_applyWalletTargetsNative", 1)[1]
    apply_w = apply_w.split("Java_com_destian_dtp_NativeGameRuntimeBridge_getWalletNative", 1)[0]
    assert "readWalletGuarded(&before)" in apply_w and "readWalletGuarded(&after)" in apply_w
    econ = cpp.split("Java_com_destian_dtp_NativeGameRuntimeBridge_applyEconomyNative", 1)[1]
    econ = econ.split("Java_com_destian_dtp_NativeGameRuntimeBridge_installEconomyHooksNative", 1)[0]
    assert "runGuarded(readEconomyBody, &econBefore)" in econ


def test_tidak_ada_pembacaan_saldo_langsung_di_jni():
    cpp = read_text("dtp/native/game_runtime_bridge.cpp")
    jni = cpp.split('extern "C" JNIEXPORT jstring JNICALL\nJava_com_destian_dtp_NativeGameRuntimeBridge_applyEconomyNative', 1)[1]
    for bad in ("getCoins(manager)", "getCrystals(manager)", "getGoblin(manager)", "getGoblinCoins(manager)"):
        assert bad not in jni, bad + " dipanggil tanpa pelindung"


def test_pelindung_meneruskan_fault_lain():
    cpp = read_text("dtp/native/game_runtime_bridge.cpp")
    handler = cpp.split("void guardSegvHandler", 1)[1].split("void installGuardHandler", 1)[0]
    assert "g_guardPrevious.sa_sigaction(sig, info, context)" in handler
    assert "signal(sig, SIG_DFL)" in handler


def test_layar_maintenance_menampilkan_detail_error():
    java = read_text("dtp/src/com/destian/dtp/MaintenanceActivity.java")
    assert "String error;" in java
    assert "r.error = e.getClass().getSimpleName()" in java
    assert '"\\nDetail: "' in java


def test_versi_17_14_6():
    yml = read_text("kingdom-in-chaos-decompiled/apktool.yml")
    assert "versionName: 1.0.6" in yml and "versionCode: 106" in yml
    assert "KingdomInChaosDTP-v1.0.6.apk" in read_text("build_dtp.py")
    assert "KingdomInChaosDTP-v1.0.6.apk" in read_text(".github/workflows/build-apk.yml")
