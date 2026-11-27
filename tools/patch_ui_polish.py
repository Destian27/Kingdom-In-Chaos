#!/usr/bin/env python3
"""Perapihan UI v17.14.5: teks Bahasa Indonesia meluap + bendera pilihan bahasa.

LATAR BELAKANG BUG (kenapa dibuat):
1) Teks meluap keluar kotak (contoh: deskripsi skill "Daya Tahan Vampir" melewati
   tepi papan, "Nilai Pertumbuhan" menimpa label "Skill", "Skill"/"Bangkit" terpotong
   di tengah kata).
   - Versi Inggris menjaga lebar dengan pemisah baris manual (&#x0A;). Contoh skill
     Vampir: baris 1 = kalimat (+-70 huruf), baris 2 = "(Casting rate: %Ds)".
   - Terjemahan Indonesia ~25% lebih panjang dan hanya satu baris (97 huruf) ->
     meluap, karena label game tidak membungkus otomatis.
   - Perbaikan: untuk setiap string, lebar acuan W = baris terpanjang versi Inggris
     (dibatasi 24..72). Baris Indonesia yang lebih panjang dari W dibungkus per kata.
     Bila versi Inggris memisahkan "(...)" di baris sendiri, versi Indonesia juga.
   - Label sempit: "Nilai Pertumbuhan" -> "Pertumbuhan" (Inggris: "Growth value"),
     "Ski\\nll" -> "Skill" (pecah di tengah kata), "Bang\\nkit" -> "Bang-\\nkit".
   - "Paket Dollar" di runtime (de.xml) -> "Paket Barter" (sudah begitu di id.xml
     sejak v17.12; runtime ketinggalan).
2) Bendera pilihan bahasa salah:
   - Slot "Bahasa Indonesia" memakai frame UI/de.png (bendera Jerman) karena runtime
     meminjam slot bahasa Jerman. Frame de di nation.plist diarahkan ke area gambar
     bendera Indonesia (UI/id.png, merah-putih). Tidak ada piksel yang diubah.
   - Slot English memakai gambar bintang tunggal (mirip Liberia). Frame UI/us.png
     digambar ulang sebagai bendera Amerika Serikat (13 garis, kanton biru, bintang).
   - nation.png dienkripsi XXTEA (kunci sama dengan DHEncrypt di build_apk.py);
     enkripsi ulang diverifikasi identik byte-per-byte pada file asli.

Skrip ini idempotent (aman dijalankan berulang).
"""
from __future__ import annotations

import io
import os
import plistlib
import re
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "kingdom-in-chaos-decompiled", "assets")
STR_DIR = os.path.join(ASSETS, "public", "config", "string")
PLIST_DIR = os.path.join(ASSETS, "release", "plist")
SUMBER = os.path.join(ROOT, "translation-source", "id.xml")
KUNCI_XXTEA = b"e3642530816912682978ad8c491ccbe7"  # 16 byte pertama dipakai

W_MIN, W_MAX = 24, 72

# ----------------------------------------------------------------- XXTEA
_D = 0x9E3779B9


def _mx(sm, y, z, p, e, k):
    return ((((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4))) ^ ((sm ^ y) + (k[(p & 3) ^ e] ^ z))) & 0xFFFFFFFF


def _key():
    return list(struct.unpack("<4I", KUNCI_XXTEA[:16]))


def xxtea_decrypt(data: bytes) -> bytes:
    v = list(struct.unpack("<%dI" % (len(data) // 4), data)); k = _key(); n = len(v)
    r = 6 + 52 // n; sm = (r * _D) & 0xFFFFFFFF; y = v[0]
    while r:
        e = (sm >> 2) & 3
        for p in range(n - 1, 0, -1):
            z = v[p - 1]; v[p] = (v[p] - _mx(sm, y, z, p, e, k)) & 0xFFFFFFFF; y = v[p]
        z = v[n - 1]; v[0] = (v[0] - _mx(sm, y, z, 0, e, k)) & 0xFFFFFFFF; y = v[0]
        sm = (sm - _D) & 0xFFFFFFFF; r -= 1
    return struct.pack("<%dI" % n, *v)


def xxtea_encrypt(data: bytes) -> bytes:
    v = list(struct.unpack("<%dI" % (len(data) // 4), data)); k = _key(); n = len(v)
    r = 6 + 52 // n; sm = 0; z = v[n - 1]
    while r:
        sm = (sm + _D) & 0xFFFFFFFF; e = (sm >> 2) & 3
        for p in range(n - 1):
            y = v[p + 1]; v[p] = (v[p] + _mx(sm, y, z, p, e, k)) & 0xFFFFFFFF; z = v[p]
        y = v[0]; v[n - 1] = (v[n - 1] + _mx(sm, y, z, n - 1, e, k)) & 0xFFFFFFFF; z = v[n - 1]
        r -= 1
    return struct.pack("<%dI" % n, *v)


def buka_png_terenkripsi(path):
    dec = xxtea_decrypt(open(path, "rb").read())
    n = struct.unpack("<I", dec[-4:])[0]  # 4 byte terakhir = panjang PNG asli
    return dec[:n]


def simpan_png_terenkripsi(path, png: bytes):
    pad = png.ljust((len(png) + 3) // 4 * 4, b"\0")
    open(path, "wb").write(xxtea_encrypt(pad + struct.pack("<I", len(png))))


# ------------------------------------------------------------------ TEKS
ITEM = re.compile(r"<i\b([^>]*)>(.*?)</i>", re.S)


def _un(t):
    return t.replace("&#x0A;", "\n")


def _norm(a):
    return re.sub(r"\s+", " ", a).strip()


def bungkus(line: str, w: int) -> list[str]:
    """Bungkus satu baris per kata; kata yang lebih panjang dari w dibiarkan utuh."""
    out, cur = [], ""
    for kata in line.split(" "):
        if cur and len(cur) + 1 + len(kata) > w:
            out.append(cur); cur = kata
        else:
            cur = (cur + " " + kata) if cur else kata
    out.append(cur)
    return out


def rapikan_teks(en_item: str, id_text: str) -> str:
    en_lines = _un(en_item).split("\n")
    w = min(W_MAX, max(W_MIN, max(len(x) for x in en_lines)))
    # Inggris memisahkan keterangan "(...)" di baris sendiri -> ikuti.
    paksa_kurung = "\n(" in _un(en_item)
    hasil = []
    for line in id_text.split("\n"):
        if paksa_kurung and not line.startswith("(") and " (" in line and len(line) > w:
            i = line.rfind(" (")
            bagian = [line[:i], line[i + 1:]]
        else:
            bagian = [line]
        for b in bagian:
            hasil.extend(bungkus(b, w) if len(b) > w else [b])
    return "\n".join(hasil)


LABEL_TETAP = {  # key -> teks baru (label sempit)
    "convert_growthValueLerlevel": "Pertumbuhan",
    "convert_skill": "Skill",
    "convert_awake": "Bang-\nkit",
}


def proses_string(en_xml: str, id_xml: str) -> str:
    en_items = list(ITEM.finditer(en_xml))
    id_items = list(ITEM.finditer(id_xml))
    if len(en_items) != len(id_items):
        raise RuntimeError("Jumlah item en/id tidak sama: %d vs %d" % (len(en_items), len(id_items)))
    out, pos = [], 0
    for me, mi in zip(en_items, id_items):
        out.append(id_xml[pos:mi.start(2)])
        teks = mi.group(2)
        mk = re.search(r'key="([^"]+)"', mi.group(1))
        if mk and mk.group(1) in LABEL_TETAP:
            teks = LABEL_TETAP[mk.group(1)]
        elif _norm(me.group(1)) == _norm(mi.group(1)):
            teks = rapikan_teks(me.group(2), teks)
        if mk and mk.group(1) in ("luckPackTitle", "promotingHintGift3"):
            teks = teks.replace("Paket Dollar", "Paket Barter")
        out.append(teks)
        pos = mi.end(2)
    out.append(id_xml[pos:])
    return "".join(out)


def baca_cfg(path):
    raw = open(path, "rb").read()
    return zlib.decompress(raw[4:]).decode("utf-8")


def tulis_cfg(path, xml):
    data = xml.encode("utf-8")
    open(path, "wb").write(struct.pack(">I", len(data)) + zlib.compress(data, 9))


def patch_teks():
    en = baca_cfg(os.path.join(STR_DIR, "us.xml"))
    for nama in ("de.xml", "id.xml"):  # de = slot runtime Indonesia, id = salinan
        p = os.path.join(STR_DIR, nama)
        lama = baca_cfg(p); baru = proses_string(en, lama)
        if baru != lama:
            tulis_cfg(p, baru); print("teks dirapikan:", nama)
    lama = open(SUMBER, encoding="utf-8").read(); baru = proses_string(en, lama)
    if baru != lama:
        open(SUMBER, "w", encoding="utf-8", newline="").write(baru); print("teks dirapikan: translation-source/id.xml")


# --------------------------------------------------------------- BENDERA
def gambar_bendera_as(frame_lama, w, h):
    """Bendera AS: 13 garis, kanton biru 40% lebar x 7 garis, 9 baris bintang."""
    from PIL import Image, ImageDraw
    S = 16
    # Palet dikunci (diambil dari bendera lama) supaya seragam dengan bendera lain
    # dan hasil patch deterministik -> idempotent.
    merah = (237, 85, 101); biru = (74, 137, 220); putih = (246, 255, 255)
    im = Image.new("RGB", (w * S, h * S), putih); d = ImageDraw.Draw(im)
    tg = h * S / 13.0
    for i in range(0, 13, 2):
        d.rectangle([0, round(i * tg), w * S, round((i + 1) * tg) - 1], fill=merah)
    kw, kh = round(w * S * 0.40), round(7 * tg)
    d.rectangle([0, 0, kw, kh], fill=biru)
    for r in range(9):
        n = 6 if r % 2 == 0 else 5
        for c in range(n):
            cx = kw * (((c * 2 + (0 if r % 2 == 0 else 1)) + 1) / 12.0)
            cy = kh * ((r + 1) / 10.0)
            rad = S * 0.42
            d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=putih)
    rgb = im.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.paste(rgb)
    # pertahankan alpha (sudut membulat) dari frame lama
    out.putalpha(frame_lama.getchannel("A"))
    return out


def patch_bendera():
    from PIL import Image
    ppl = os.path.join(PLIST_DIR, "nation.plist")
    png = os.path.join(PLIST_DIR, "nation.png")
    data = plistlib.load(open(ppl, "rb")); fr = data["frames"]
    # 1) slot Bahasa Indonesia (frame "de") -> bendera Indonesia (frame "id")
    if fr["UI/de.png"] != fr["UI/id.png"]:
        fr["UI/de.png"] = dict(fr["UI/id.png"])
        plistlib.dump(data, open(ppl, "wb")); print("nation.plist: frame de -> bendera Indonesia (id)")
    # 2) bendera English (frame "us") -> bendera Amerika Serikat yang benar
    img = Image.open(io.BytesIO(buka_png_terenkripsi(png))).convert("RGBA")
    x, y, w, h = map(int, re.findall(r"\d+", fr["UI/us.png"]["frame"]))
    lama = img.crop((x, y, x + w, y + h))
    baru = gambar_bendera_as(lama, w, h)
    if lama.tobytes() != baru.tobytes():
        img.paste(baru, (x, y))
        buf = io.BytesIO(); img.save(buf, "PNG", optimize=True)
        simpan_png_terenkripsi(png, buf.getvalue()); print("nation.png: bendera US digambar ulang")


def main():
    patch_teks()
    patch_bendera()


if __name__ == "__main__":
    main()
