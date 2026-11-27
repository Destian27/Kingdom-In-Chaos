#!/usr/bin/env python3
"""v17.14.11 — label harga di layar Penawaran memakai nominal DM, bukan Rp.

Yang diubah (hanya data, tanpa menyentuh logika native):
  1. price.xml: sign="Rp" -> sign="DM" dan elemen <dollar> diisi nominal
     barter (sama dengan tabel getOfferCost() di game_runtime_bridge.cpp).
  2. libgame.so (armeabi & armeabi-v7a): format "%s%.2f" -> "%s%.0f"
     (panjang sama, 1 byte) supaya tombol tampil "DM299", bukan "Rp299.00".

Catatan: nilai ini HANYA label. Pemotongan saldo tetap lewat dtpPricePayHook.
Catatan: handlePaidOK() menambah harga item ke progres Total Recharge, jadi
nilai item berbayar Koin harus setara DM (bukan angka Koin) agar tidak langsung
mencapai 1.000.
Skrip idempoten: aman dijalankan berulang.
"""
import os, re, struct, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEC = os.path.join(ROOT, "kingdom-in-chaos-decompiled")
PRICE = os.path.join(DEC, "assets", "public", "config", "price.xml")
SIGN = "DM"

# Urutan unlockHero mengikuti heroCosts[] di bridge (ASUMSI, belum diuji di game).
NILAI = {
    "unlockHero3": 140, "unlockHero6": 350, "unlockHero8": 1400,
    "unlockHero12": 490, "unlockHero14": 490, "unlockHero15": 700,
    "rookieGifts00": 299, "rookieGifts10": 999,
    "coinPrice0": 200, "coinPrice1": 700, "coinPrice2": 2400,      # DM -> Koin
    "crystalPrice0": 200, "crystalPrice1": 700, "crystalPrice2": 2400,  # dibayar KOIN; label = setara DM (50 Koin = 1 DM)
    "weekPack": 599, "pvpTicket": 99,
    "monthCard": 600,     # v17.14.15: dibayar 600 DM (Kristal)
    "propItem": 499,
    "luckGift": 70,       # v17.14.15: dibayar 70 DM (Kristal)
    "heroPackGift": 560, "gearPackGift": 420,
    "christmas0": 499, "christmas1": 1499,
}


def patch_price():
    raw = open(PRICE, "rb").read()
    xml = zlib.decompress(raw[4:]).decode("utf-8")
    m = re.search(r"<dollar>.*?</dollar>", xml, flags=re.DOTALL)
    if not m:
        raise RuntimeError("blok <dollar> tidak ditemukan")
    blok = re.sub(r'<cn sign="[^"]*">', '<cn sign="%s">' % SIGN, m.group(0))
    for k, v in NILAI.items():
        blok, n = re.subn(r"<%s>[^<]*</%s>" % (k, k), "<%s>%d</%s>" % (k, v, k), blok)
        if n != 1:
            raise RuntimeError("elemen %s tidak ditemukan tepat sekali" % k)
    baru = xml[:m.start()] + blok + xml[m.end():]
    if baru == xml:
        print("price.xml: tidak ada perubahan")
        return
    data = baru.encode("utf-8")
    open(PRICE, "wb").write(struct.pack(">I", len(data)) + zlib.compress(data, 9))
    print("price.xml: sign=%s, %d nominal DM/Koin diisi" % (SIGN, len(NILAI)))


def patch_libs():
    old, new = b"%s%.2f\x00", b"%s%.0f\x00"
    for abi in ("armeabi", "armeabi-v7a"):
        p = os.path.join(DEC, "lib", abi, "libgame.so")
        d = bytearray(open(p, "rb").read())
        if d.count(old) == 0:
            print(abi, ": sudah dipatch" if d.count(new) else ": format tidak ditemukan")
            continue
        if d.count(old) != 1:
            raise RuntimeError("%s: format ambigu (%d)" % (abi, d.count(old)))
        i = d.find(old)
        d[i:i + len(old)] = new
        open(p, "wb").write(d)
        print(abi, ": format harga %s%.2f -> %s%.0f @", hex(i))


if __name__ == "__main__":
    patch_price()
    patch_libs()
