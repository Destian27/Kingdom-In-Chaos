#!/usr/bin/env python3
"""v1.0.8: arahkan permintaan login/daftar/ubah-akun bawaan game ke server lokal di dalam aplikasi.

Dialog Masuk/Daftar BAWAAN game (UIPopupLogIn / UIPopupSignUpAccount / UIPopupSignUpInfo) memanggil
NetworkManager::logIn / signUp / modifyAccount. Fungsi itu menyusun URL dengan sprintf dari tiga string
format di libgame.so. Skrip ini hanya mengganti AWALAN ketiga string itu dengan alamat loopback
http://127.0.0.1:7391/ (panjang awalan SAMA persis, sisa string tidak disentuh). Argumen host pertama
tetap dikonsumsi lewat %.0s agar urutan argumen sprintf tidak berubah.
Aman dijalankan ulang (idempoten).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBS = [
    os.path.join(ROOT, "kingdom-in-chaos-decompiled", "lib", "armeabi-v7a", "libgame.so"),
    os.path.join(ROOT, "kingdom-in-chaos-decompiled", "lib", "armeabi", "libgame.so"),
]
PORT = 7391
BASE = "http://127.0.0.1:%d/%%.0s" % PORT
PATCHES = [
    (b"http://%s/ph/boss/login_v16.php?", (BASE + "login?").encode()),
    (b"http://%s/ph/boss/signup_v16.php?", (BASE + "signup?").encode()),
    (b"http://%s/ph/boss/modify.php?", (BASE + "mo?").encode()),
]


def patch(path):
    if not os.path.exists(path):
        return 0
    data = bytearray(open(path, "rb").read())
    changed = 0
    for old, new in PATCHES:
        assert len(old) == len(new), (old, new, len(old), len(new))
        already = data.count(new)
        hits = data.count(old)
        if hits == 0 and already == 1:
            continue
        if hits != 1:
            sys.exit("%s: %r ditemukan %d kali (harus 1)" % (path, old, hits))
        pos = data.find(old)
        assert pos > 0 and data[pos - 1] == 0, "awal string tidak berdiri sendiri"
        data[pos:pos + len(old)] = new
        changed += 1
    if changed:
        open(path, "wb").write(bytes(data))
    return changed


if __name__ == "__main__":
    total = 0
    for lib in LIBS:
        n = patch(lib)
        print("%s: %d string diganti" % (os.path.relpath(lib, ROOT), n))
        total += n
    print("selesai")
