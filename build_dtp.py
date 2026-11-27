import glob
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
DECOMPILED = os.path.join(ROOT, "kingdom-in-chaos-decompiled")
JAVA_SRC = os.path.join(ROOT, "dtp", "src")
TOOLS = os.path.join(ROOT, "tools")
BUILD = os.path.join(ROOT, "build_dtp")
APKTOOL_JAR = os.environ.get("APKTOOL_JAR", os.path.join(TOOLS, "apktool.jar"))
KEYSTORE = os.environ.get("KEYSTORE_PATH", os.path.join(TOOLS, "release.keystore"))
KS_PASS = os.environ.get("KEYSTORE_PASS", "android123")
KS_ALIAS = os.environ.get("KEYSTORE_ALIAS", "kingdomchaosdtp")
OUTPUT_APK = os.path.join(ROOT, "KingdomInChaosDTP-v17.14.8-price-barter-crashfix.apk")
MIN_API = "24"
NDK_VERSION = os.environ.get("ANDROID_NDK_VERSION", "27.2.12479018")
IS_WIN = os.name == "nt"


def run(cmd, **kw):
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True, **kw)


def sdk_root():
    for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        p = os.environ.get(key)
        if p and os.path.isdir(p):
            return p
    sys.exit("ANDROID_HOME / ANDROID_SDK_ROOT tidak ditemukan")


def latest(pattern):
    items = sorted(glob.glob(pattern), key=lambda p: [int(x) if x.isdigit() else 0 for x in os.path.basename(p).replace("android-", "").split(".")])
    if not items:
        sys.exit("Tidak ketemu: " + pattern)
    return items[-1]


def bt(name):
    build_tools = latest(os.path.join(sdk_root(), "build-tools", "*"))
    ext = {"d8": ".bat", "apksigner": ".bat", "zipalign": ".exe"} if IS_WIN else {}
    return os.path.join(build_tools, name + ext.get(name, ""))


def android_jar():
    for plat in sorted(glob.glob(os.path.join(sdk_root(), "platforms", "android-*")), reverse=True):
        jar = os.path.join(plat, "android.jar")
        if os.path.exists(jar):
            return jar
    sys.exit("android.jar tidak ditemukan, install platform Android SDK")


def ndk_root():
    for key in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        value = os.environ.get(key)
        if value and os.path.isdir(value):
            return value
    exact = os.path.join(sdk_root(), "ndk", NDK_VERSION)
    if os.path.isdir(exact):
        return exact
    candidates = glob.glob(os.path.join(sdk_root(), "ndk", "*"))
    candidates = [p for p in candidates if os.path.isdir(p)]
    if candidates:
        return sorted(candidates)[-1]
    sys.exit("Android NDK tidak ditemukan. Install NDK " + NDK_VERSION + " atau set ANDROID_NDK_HOME")


def patch_native_barter():
    patcher = os.path.join(TOOLS, "patch_barter_native.py")
    if not os.path.isfile(patcher):
        sys.exit("Script patch barter native tidak ditemukan: " + patcher)
    run([sys.executable, patcher])


def patch_lifemax_crash():
    patcher = os.path.join(TOOLS, "patch_lifemax_crash.py")
    if not os.path.isfile(patcher):
        sys.exit("Script crash guard LifeMax tidak ditemukan: " + patcher)
    run([sys.executable, patcher])


def patch_price_dollar_fix():
    # v17.14.4: isi elemen harga dolar yang kosong di price.xml (penyebab SIGSEGV
    # DHValue::getValue saat game dibuka).
    patcher = os.path.join(TOOLS, "patch_price_dollar_fix.py")
    if not os.path.isfile(patcher):
        sys.exit("Script patch price dolar tidak ditemukan: " + patcher)
    run([sys.executable, patcher])


def patch_ui_polish():
    # v17.14.5: rapikan teks Indonesia yang meluap + perbaiki bendera pilihan bahasa.
    patcher = os.path.join(TOOLS, "patch_ui_polish.py")
    if not os.path.isfile(patcher):
        sys.exit("Script perapihan UI tidak ditemukan: " + patcher)
    run([sys.executable, patcher])


def compile_native_bridge():
    ndk = ndk_root()
    host = "windows-x86_64" if IS_WIN else ("darwin-arm64" if sys.platform == "darwin" and os.uname().machine == "arm64" else "darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64")
    prebuilt = os.path.join(ndk, "toolchains", "llvm", "prebuilt", host)
    compiler = os.path.join(prebuilt, "bin", "clang++.exe" if IS_WIN else "clang++")
    if not os.path.isfile(compiler):
        sys.exit("NDK clang++ tidak ditemukan: " + compiler)
    source = os.path.join(ROOT, "dtp", "native", "game_runtime_bridge.cpp")
    target_dir = os.path.join(DECOMPILED, "lib", "armeabi-v7a")
    os.makedirs(target_dir, exist_ok=True)
    output = os.path.join(target_dir, "libkicgamebridge.so")
    cmd = [compiler, "--target=armv7a-linux-androideabi" + MIN_API,
           "--sysroot=" + os.path.join(prebuilt, "sysroot"),
           "-shared", "-fPIC", "-mthumb", "-std=c++17", "-O2", "-nostdlib++",
           "-Wl,--no-undefined", "-Wl,-soname,libkicgamebridge.so",
           "-o", output, source, "-ldl"]
    run(cmd)
    if not os.path.isfile(output) or os.path.getsize(output) < 1024:
        sys.exit("Native bridge .so tidak berhasil dibuat")
    print("Native game bridge:", output, os.path.getsize(output), "bytes")


def ensure_keystore():
    if os.path.exists(KEYSTORE):
        return
    os.makedirs(os.path.dirname(KEYSTORE), exist_ok=True)
    run([
        "keytool", "-genkeypair", "-keystore", KEYSTORE, "-alias", KS_ALIAS,
        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
        "-storepass", KS_PASS, "-keypass", KS_PASS,
        "-dname", "CN=Kingdom In Chaos DTP, OU=DTP, O=Destian, L=ID, S=ID, C=ID",
    ])


def compile_dex():
    shutil.rmtree(BUILD, ignore_errors=True)
    classes = os.path.join(BUILD, "classes")
    dex_out = os.path.join(BUILD, "dex")
    os.makedirs(classes)
    os.makedirs(dex_out)
    jar = android_jar()
    sources = glob.glob(os.path.join(JAVA_SRC, "**", "*.java"), recursive=True)
    run(["javac", "--release", "8", "-Xlint:-options", "-classpath", jar, "-d", classes] + sources)
    class_files = glob.glob(os.path.join(classes, "**", "*.class"), recursive=True)
    run([bt("d8"), "--release", "--min-api", MIN_API, "--lib", jar, "--output", dex_out] + class_files)
    return os.path.join(dex_out, "classes.dex")


def add_dex(apk_in, apk_out, dex_path):
    with zipfile.ZipFile(apk_in) as zin:
        names = zin.namelist()
        n = 2
        while "classes%d.dex" % n in names:
            n += 1
        new_name = "classes%d.dex" % n
        with zipfile.ZipFile(apk_out, "w") as zout:
            for item in zin.infolist():
                zout.writestr(item, zin.read(item.filename), compress_type=item.compress_type)
            zout.write(dex_path, new_name, compress_type=zipfile.ZIP_DEFLATED)
    print("Menambahkan", new_name)


def main():
    if not os.path.exists(APKTOOL_JAR):
        sys.exit("apktool.jar tidak ada: " + APKTOOL_JAR)
    patch_native_barter()
    patch_lifemax_crash()
    patch_price_dollar_fix()
    patch_ui_polish()
    compile_native_bridge()
    dex = compile_dex()

    unsigned = os.path.join(BUILD, "unsigned.apk")
    with_dex = os.path.join(BUILD, "with_dex.apk")
    aligned = os.path.join(BUILD, "aligned.apk")
    run(["java", "-jar", APKTOOL_JAR, "b", DECOMPILED, "-o", unsigned])
    add_dex(unsigned, with_dex, dex)
    run([bt("zipalign"), "-p", "-f", "4", with_dex, aligned])

    ensure_keystore()
    if os.path.exists(OUTPUT_APK):
        os.remove(OUTPUT_APK)
    run([
        bt("apksigner"), "sign", "--ks", KEYSTORE,
        "--ks-pass", "pass:" + KS_PASS, "--key-pass", "pass:" + KS_PASS,
        "--ks-key-alias", KS_ALIAS,
        "--v1-signing-enabled", "true", "--v2-signing-enabled", "true", "--v3-signing-enabled", "true",
        "--out", OUTPUT_APK, aligned,
    ])
    run([bt("apksigner"), "verify", "--verbose", OUTPUT_APK])
    print("Selesai:", OUTPUT_APK, os.path.getsize(OUTPUT_APK), "bytes")


if __name__ == "__main__":
    main()
