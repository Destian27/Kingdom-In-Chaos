import os
import glob
import re
import struct
import subprocess
import unittest
import zipfile
import zlib

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DECOMPILED_DIR = os.path.join(REPO_ROOT, "kingdom-in-chaos-decompiled")
TOOLS_DIR = os.path.join(REPO_ROOT, "tools")
OUTPUT_APK = os.path.join(REPO_ROOT, "KingdomInChaosDTP.apk")


def find_build_tool(name):
    sdk_root = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if sdk_root:
        roots = sorted(glob.glob(os.path.join(sdk_root, "build-tools", "*")))
        for root in reversed(roots):
            for candidate in [name, name + ".exe", name + ".bat"]:
                path = os.path.join(root, candidate)
                if os.path.isfile(path):
                    return path
    return None


AAPT2_EXE = find_build_tool("aapt2")
APKSIGNER = find_build_tool("apksigner")


def has_textrel(elf_bytes: bytes) -> bool:
    e_phoff, _, _, _, e_phentsize, e_phnum = struct.unpack_from("<IIIHHH", elf_bytes, 28)
    dyn_off, dyn_sz = 0, 0
    for i in range(e_phnum):
        p_type, p_offset, _, _, p_filesz, _, _, _ = struct.unpack_from(
            "<IIIIIIII", elf_bytes, e_phoff + i * e_phentsize
        )
        if p_type == 2:  # PT_DYNAMIC
            dyn_off, dyn_sz = p_offset, p_filesz
    for pos in range(dyn_off, dyn_off + dyn_sz, 8):
        d_tag, d_val = struct.unpack_from("<iI", elf_bytes, pos)
        if d_tag == 0:
            break
        if d_tag == 22 or (d_tag == 30 and (d_val & 0x4)):
            return True
    return False


class TestKingdomInChaosAndroid13Port(unittest.TestCase):
    def test_apktool_yml_target_sdk_is_modern(self):
        yml_path = os.path.join(DECOMPILED_DIR, "apktool.yml")
        with open(yml_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("targetSdkVersion: 28", content)
        self.assertIn("minSdkVersion: 24", content)

    def test_dtp_rename_package_and_label(self):
        manifest_path = os.path.join(DECOMPILED_DIR, "AndroidManifest.xml")
        with open(manifest_path, "r", encoding="utf-8") as f:
            xml = f.read()
        self.assertIn('package="com.destian.kingdominchaosdtp"', xml)
        strings_path = os.path.join(DECOMPILED_DIR, "res", "values", "strings.xml")
        with open(strings_path, "r", encoding="utf-8") as f:
            self.assertIn(">Kingdom In Chaos DTP<", f.read())

    def test_dtp_maintenance_is_launcher_and_game_not_exported(self):
        manifest_path = os.path.join(DECOMPILED_DIR, "AndroidManifest.xml")
        with open(manifest_path, "r", encoding="utf-8") as f:
            xml = f.read()
        self.assertIn('android:name="com.destian.dtp.MaintenanceActivity"', xml)
        self.assertIn('android:name="com.droidhang.ph.GameActivity" android:exported="false"', xml)
        self.assertEqual(xml.count("android.intent.category.LAUNCHER"), 1)
        src = os.path.join(os.path.dirname(DECOMPILED_DIR), "dtp", "src", "com", "destian", "dtp", "MaintenanceActivity.java")
        self.assertTrue(os.path.exists(src))

    def test_manifest_has_http_legacy_and_cleartext_and_exported(self):
        manifest_path = os.path.join(DECOMPILED_DIR, "AndroidManifest.xml")
        with open(manifest_path, "r", encoding="utf-8") as f:
            xml = f.read()
        self.assertIn('platformBuildVersionCode="28"', xml)
        self.assertIn('android:requestLegacyExternalStorage="true"', xml)
        self.assertIn('android:name="org.apache.http.legacy"', xml)
        self.assertIn('android:usesCleartextTraffic="true"', xml)
        self.assertIn('android:name="com.destian.dtp.MaintenanceActivity" android:exported="true"', xml)
        self.assertIn('android:name="com.droidhang.ph.GameActivity" android:exported="false"', xml)
        self.assertNotIn('android.permission.READ_PHONE_STATE', xml)
        self.assertIn(
            'android:enabled="false" android:exported="false" android:name="com.vungle.publisher.VungleService"',
            xml,
        )
        self.assertIn(
            'android:enabled="false" android:exported="false" android:name="com.sponsorpay.advertiser.InstallReferrerReceiver"',
            xml,
        )
        self.assertIn(
            'android:enabled="false" android:exported="false" android:name="com.hz.game.be.FyberReceiver"',
            xml,
        )

    def test_built_and_signed_apk_is_valid_for_android_13_plus(self):
        if not os.path.isfile(OUTPUT_APK):
            self.skipTest("Build_dtp.py has not produced KingdomInChaosDTP.apk yet")
        if not AAPT2_EXE or not APKSIGNER:
            self.skipTest("Android SDK build tools are not configured for this environment")

        badging = subprocess.run(
            [AAPT2_EXE, "dump", "badging", OUTPUT_APK],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=True,
        ).stdout
        self.assertIn("targetSdkVersion:'28'", badging)

        sig = subprocess.run(
            [APKSIGNER, "verify", "--verbose", OUTPUT_APK],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=True,
        ).stdout
        self.assertIn("Verified using v1 scheme (JAR signing): true", sig)
        self.assertIn("Verified using v2 scheme (APK Signature Scheme v2): true", sig)

    def test_fix2_no_obsolete_libraries_in_source(self):
        lib_dir = os.path.join(DECOMPILED_DIR, "lib")
        for bad_lib in ["libbspatch.so", "libgetuiext.so", "libNativeCrash.so"]:
            for root, _, files in os.walk(lib_dir):
                self.assertNotIn(
                    bad_lib,
                    files,
                    f"Obsolete library {bad_lib} still exists in {root}",
                )

    def test_fix2_armeabi_and_v7a_exist_and_clean_of_textrel(self):
        lib_dir = os.path.join(DECOMPILED_DIR, "lib")
        for abi in ["armeabi", "armeabi-v7a"]:
            abi_dir = os.path.join(lib_dir, abi)
            self.assertTrue(os.path.isdir(abi_dir), f"{abi} directory missing")
            so_path = os.path.join(abi_dir, "libgame.so")
            self.assertTrue(os.path.isfile(so_path), f"libgame.so missing in {abi}")
            with open(so_path, "rb") as f:
                elf = f.read()
            self.assertFalse(
                has_textrel(elf),
                f"libgame.so in {abi} contains DT_TEXTREL, which crashes Android 6.0+",
            )

    def test_fix2_packaged_apk_native_structure(self):
        if not os.path.isfile(OUTPUT_APK):
            self.skipTest("Build_dtp.py has not produced an APK yet")
        with zipfile.ZipFile(OUTPUT_APK, "r") as zf:
            namelist = zf.namelist()
            self.assertIn("lib/armeabi/libgame.so", namelist)
            self.assertIn("lib/armeabi-v7a/libgame.so", namelist)
            for name in namelist:
                self.assertNotIn("libbspatch.so", name)
                self.assertNotIn("libgetuiext.so", name)
                self.assertNotIn("libNativeCrash.so", name)

    def test_fix3_no_floatmath_references(self):
        bitmap_smali = os.path.join(
            DECOMPILED_DIR, "smali", "org", "cocos2dx", "lib", "Cocos2dxBitmap.smali"
        )
        with open(bitmap_smali, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertNotIn(
            "Landroid/util/FloatMath;",
            content,
            "Cocos2dxBitmap still references removed Android FloatMath",
        )
        self.assertIn(".method private static ceilFloat(F)F", content)

    def test_fix4_cocos2dx_renderer_lifecycle_guards(self):
        renderer_smali = os.path.join(
            DECOMPILED_DIR, "smali", "org", "cocos2dx", "lib", "Cocos2dxRenderer.smali"
        )
        with open(renderer_smali, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn(".field public static sNativeInitDone:Z", content)
        self.assertIn(
            "sput-boolean v2, Lorg/cocos2dx/lib/Cocos2dxRenderer;->sNativeInitDone:Z",
            content,
        )
        self.assertIn(
            "sget-boolean v0, Lorg/cocos2dx/lib/Cocos2dxRenderer;->sNativeInitDone:Z",
            content,
        )
        self.assertIn(
            "sget-boolean v4, Lorg/cocos2dx/lib/Cocos2dxRenderer;->sNativeInitDone:Z",
            content,
        )

    def test_fix5_signature_spoofed_and_telemetry_neutralized(self):
        # 1. Smali signature spoof check
        android_util = os.path.join(
            DECOMPILED_DIR, "smali", "com", "wwcd", "util", "AndroidUtil.smali"
        )
        with open(android_util, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('const-string v0, "e3642530816912682978ad8c491ccbe7"', content)

        # 2. Native patch checks
        expected_patches = {
            0x0025DDD4: bytes.fromhex("7047" + "c046" * 9),
            0x003DEB18: b"\x70\x47",
            0x0062E40C: b"\x1e\xff\x2f\xe1",
            0x0062F1D0: b"\x1e\xff\x2f\xe1",
            0x0062F028: b"\x1e\xff\x2f\xe1",
            0x0062E5C8: b"\x1e\xff\x2f\xe1",
            0x0062E57C: b"\x1e\xff\x2f\xe1",
            0x00441CC0: b"\x70\x47",
            0x00441824: b"\x70\x47",
            0x00441F04: b"\x70\x47",
            0x00441CE0: b"\x70\x47",
            0x00441DB0: b"\x70\x47",
            0x00441E34: b"\x70\x47",
            0x00441EE8: b"\x70\x47",
            0x00441F20: b"\x70\x47",
            0x003DA62C: b"\x70\x47",
        }
        for abi in ["armeabi", "armeabi-v7a"]:
            so_path = os.path.join(DECOMPILED_DIR, "lib", abi, "libgame.so")
            with open(so_path, "rb") as f:
                data = f.read()
            for off, expected in expected_patches.items():
                actual = data[off : off + len(expected)]
                self.assertEqual(
                    actual,
                    expected,
                    f"Patch mismatch at 0x{off:08X} in {abi}/libgame.so",
                )

    def test_fix6_stamina_system_unlimited_and_clean_ui(self):
        balance_patch = bytes.fromhex("002802d005220260002902d000220a607047")
        decrease_patch = b"\x01\x20\x70\x47"

        for abi in ["armeabi", "armeabi-v7a"]:
            so_path = os.path.join(DECOMPILED_DIR, "lib", abi, "libgame.so")
            with open(so_path, "rb") as f:
                data = f.read()

            self.assertEqual(
                data[0x003053A0 : 0x003053A0 + len(balance_patch)],
                balance_patch,
                f"BalanceLifeStatus patch mismatch in {abi}/libgame.so",
            )
            self.assertEqual(
                data[0x003055FC : 0x003055FC + len(decrease_patch)],
                decrease_patch,
                f"DecreaseLife patch mismatch in {abi}/libgame.so",
            )

    def test_fix7_original_hero_purchase_flow_preserved(self):
        # Normal hero lock/payment routines are restored; the former forced-unlock
        # and free-purchase stubs must not remain.
        hero_expected = {
            0x002E17DC: bytes.fromhex("70b584b0"),  # normal routine prologue
            0x0038C03C: b"\x70\x47",  # existing visual-lock helper patch retained
            0x002B9AD4: bytes.fromhex("10b5041c"),  # normal payUnlockHero prologue
        }

        for abi in ["armeabi", "armeabi-v7a"]:
            so_path = os.path.join(DECOMPILED_DIR, "lib", abi, "libgame.so")
            with open(so_path, "rb") as f:
                data = f.read()

            for off, expected in hero_expected.items():
                actual = data[off : off + len(expected)]
                self.assertEqual(
                    actual,
                    expected,
                    f"Hero purchase-flow bytes mismatch at 0x{off:08X} in {abi}/libgame.so",
                )

    def test_fix8_be_util_focus_guarded_and_ads_stubbed(self):
        be_util_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "hz", "game", "be", "util", "BEUtil.smali"
        )
        with open(be_util_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("sget-boolean v0, Lorg/cocos2dx/lib/Cocos2dxRenderer;->sNativeInitDone:Z", content)
        self.assertIn("com.destian.kingdominchaosdtp", content)
        self.assertNotIn("com.hz.game.be/shared_prefs", content)

        be8_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "hz", "game", "be", "util", "BEUtil$8.smali"
        )
        with open(be8_path, "r", encoding="utf-8") as f:
            content8 = f.read()
        self.assertIn("sget-boolean v0, Lorg/cocos2dx/lib/Cocos2dxRenderer;->sNativeInitDone:Z", content8)

    def test_fix9_game_activity_dead_sdks_neutralized(self):
        ga_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "droidhang", "ph", "GameActivity.smali"
        )
        with open(ga_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("# invoke-static {p0}, Lcom/umeng/analytics/MobclickAgent;->noop_updateOnlineConfig(Landroid/content/Context;)V", content)
        self.assertIn("# invoke-static {p0, v0, v1}, Lcom/tapjoy/TapjoyConnect;->noop_requestTapjoyConnect(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Z", content)
        self.assertIn("# invoke-static {p0, p0, p0}, Lcom/droidhang/game/DHGames;->noop_init(Landroid/app/Activity;Lcom/droidhang/game/ad/IAdId;Lcom/droidhang/game/ad/video/VideoAdCallback;)V", content)
        self.assertIn("# invoke-static {p0, v0}, Lcom/droidhang/crosspromotion/CrossPromotionUtil;->noop_init(Landroid/app/Activity;Landroid/widget/FrameLayout;)V", content)
        self.assertIn("# invoke-virtual {v0, v1, v2, p0, v3}, Lcom/droidhang/pay/DHGooglePaymentManager;->noop_init(Ljava/lang/String;ILandroid/app/Activity;Landroid/opengl/GLSurfaceView;)V", content)
        self.assertIn("# invoke-static {p0, v0}, Lcom/hz/game/be/util/AdMgr;->noop_init(Landroid/app/Activity;Landroid/widget/RelativeLayout;)V", content)
        self.assertIn("# invoke-static {p0, v4, v4}, Lcom/hz/game/be/util/AdMgr;->noop_enable(Landroid/app/Activity;II)V", content)

    def test_fix10_testin_agent_neutralized(self):
        testin_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "testin", "agent", "TestinAgent.smali"
        )
        with open(testin_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn(".method public static init(Landroid/content/Context;)V\n    .locals 0\n    return-void\n.end method", content)
        self.assertIn(".method private static isOK()Z\n    .locals 1\n    const/4 v0, 0x0\n    return v0\n.end method", content)

        b_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "testin", "agent", "e", "b.smali"
        )
        with open(b_path, "r", encoding="utf-8") as f:
            b_content = f.read()
        self.assertIn(".method public static a(Landroid/content/Context;)Z\n    .locals 1\n    const/4 v0, 0x0\n    return v0\n.end method", b_content)

    def test_fix11_dh_google_payment_safe(self):
        pay_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "droidhang", "pay", "DHGooglePaymentManager.smali"
        )
        with open(pay_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("iput-boolean v0, p0, Lcom/droidhang/pay/DHGooglePaymentManager;->supportPurchase:Z", content)
        self.assertNotIn("invoke-direct {p0}, Lcom/droidhang/pay/DHGooglePaymentManager;->initPurchase()V", content)
        self.assertIn("if-nez v0, :cond_0", content)

    def test_fix12_io_util_delete_null_safe(self):
        io_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "wwcd", "util", "IOUtil.smali"
        )
        with open(io_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("if-nez v2, :cond_io_not_null", content)

    def test_fix13_android_util_stubs_safe(self):
        au_path = os.path.join(
            DECOMPILED_DIR, "smali", "com", "wwcd", "util", "AndroidUtil.smali"
        )
        with open(au_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('const-string v0, "02:00:00:00:00:00"', content)
        self.assertNotIn("invoke-virtual {v1}, Landroid/net/wifi/WifiManager;->getConnectionInfo()Landroid/net/wifi/WifiInfo;", content)

    def test_fix14_preload_layer_and_helper_init_safe(self):
        # 1. Native patches for PreloadLayer
        expected_preload = {
            0x00271546: b"\xc7\xe0",
            0x0027173E: bytes.fromhex("0028cad0"),
        }
        for abi in ["armeabi", "armeabi-v7a"]:
            so_path = os.path.join(DECOMPILED_DIR, "lib", abi, "libgame.so")
            with open(so_path, "rb") as f:
                data = f.read()
            for off, expected in expected_preload.items():
                actual = data[off : off + len(expected)]
                self.assertEqual(
                    actual,
                    expected,
                    f"PreloadLayer patch mismatch at 0x{off:08X} in {abi}/libgame.so",
                )

        # 2. Smali ordering: Cocos2dxHelper.init before Cocos2dxActivity.init
        activity_path = os.path.join(
            DECOMPILED_DIR, "smali", "org", "cocos2dx", "lib", "Cocos2dxActivity.smali"
        )
        with open(activity_path, "r", encoding="utf-8") as f:
            act = f.read()
        helper_idx = act.find("Lorg/cocos2dx/lib/Cocos2dxHelper;->init(")
        init_idx = act.find("invoke-virtual {p0}, Lorg/cocos2dx/lib/Cocos2dxActivity;->init()V")
        self.assertNotEqual(helper_idx, -1)
        self.assertNotEqual(init_idx, -1)
        self.assertLess(
            helper_idx,
            init_idx,
            "Cocos2dxHelper.init must be called before Cocos2dxActivity.init() to prevent race conditions",
        )

    def test_fix15_texture_null_guard_and_dhencrypt_key(self):
        expected_patches = {
            0x0047B4FC: bytes.fromhex("048d2200"),
            0x003D8F66: bytes.fromhex("0ce0"),
            0x00484472: bytes.fromhex("5df6b5b900bf"),
            0x002E17E0: bytes.fromhex("002801d0383000787047"),
        }
        for abi in ["armeabi", "armeabi-v7a"]:
            so_path = os.path.join(DECOMPILED_DIR, "lib", abi, "libgame.so")
            with open(so_path, "rb") as f:
                data = f.read()
            for off, expected in expected_patches.items():
                actual = data[off : off + len(expected)]
                self.assertEqual(
                    actual,
                    expected,
                    f"Texture/DHEncrypt patch mismatch at 0x{off:08X} in {abi}/libgame.so",
                )

    def test_fix16_unlimited_currency_injection_removed(self):
        for abi in ["armeabi", "armeabi-v7a"]:
            so_path = os.path.join(DECOMPILED_DIR, "lib", abi, "libgame.so")
            with open(so_path, "rb") as f:
                data = f.read()
            self.assertEqual(data[0x002DFA94:0x002DFA98], bytes.fromhex("30b585b0"))
            self.assertNotEqual(data[0x002DFA94:0x002DFA98], bytes.fromhex("25f08ebc"))
            self.assertNotEqual(
                data[0x003053B4:0x003053B4 + 20],
                bytes.fromhex("0a1c133a022a04d844f23f20c0f20f00704730b585b0daf765bb"),
            )

    def test_fix17_top_up_hidden_but_crystal_shop_enabled(self):
        for abi in ["armeabi", "armeabi-v7a"]:
            so_path = os.path.join(DECOMPILED_DIR, "lib", abi, "libgame.so")
            with open(so_path, "rb") as f:
                data = f.read()
            self.assertEqual(data[0x0035769E:0x003576A0], bytes.fromhex("c046"))
            self.assertEqual(data[0x00358958:0x0035895A], bytes.fromhex("7047"))

    def test_crystal_shop_packed_configs(self):
        config_dir = os.path.join(DECOMPILED_DIR, "assets", "public", "config")

        def read_xml(filename):
            with open(os.path.join(config_dir, filename), "rb") as f:
                packed = f.read()
            self.assertGreater(len(packed), 6)
            self.assertEqual(packed[4], 0x78, f"{filename} should be prefixed zlib XML")
            return zlib.decompress(packed[4:]).decode("utf-8")

        hero_xml = read_xml("hero.xml")
        expected_heroes = {"3": "140", "6": "350", "8": "1400", "12": "490", "14": "490", "15": "700"}
        for key, cost in expected_heroes.items():
            match = re.search(
                rf'<role\b[^>]*\bkey\s*=\s*["\']{key}["\'][^>]*>.*?</role>',
                hero_xml,
                flags=re.DOTALL,
            )
            self.assertIsNotNone(match, f"Hero key {key} missing")
            self.assertRegex(match.group(0), rf'<unlockCost\s+type="1">{cost}</unlockCost>')

        price_xml = read_xml("price.xml")
        expected_values = {
            "gearGroupGiftCostType0": "1", "gearGroupGiftCostValue0": "70",
            "gearGroupGiftCostType1": "1", "gearGroupGiftCostValue1": "350",
            "gearGroupGiftCostType2": "1", "gearGroupGiftCostValue2": "280",
            "gearGroupGiftBuyType": "1", "gearGroupGiftBuyValue": "420",
            "heroGroupGiftBuyType": "1", "heroGroupGiftBuyValue": "560",
            "weekGiftCostType0": "1", "weekGiftCostValue0": "490",
            "weekGiftCostType1": "1", "weekGiftCostValue1": "392",
            "weekGiftCostType2": "1", "weekGiftCostValue2": "224",
            "luckGiftCostType0": "1", "luckGiftCostValue0": "210",
            "luckGiftCostType1": "1", "luckGiftCostValue1": "140",
        }
        for tag, value in expected_values.items():
            self.assertRegex(price_xml, rf'<{tag}>{value}</{tag}>')


if __name__ == "__main__":
    unittest.main()
