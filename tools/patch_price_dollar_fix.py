#!/usr/bin/env python3
"""Perbaikan crash start game (v17.14.4): elemen harga dolar kosong di price.xml.

LATAR BELAKANG BUG (kenapa dibuat):
- Sejak v17.12 (Barter Economy), seluruh harga dolar di <dollar><cn> dikosongkan
  (<unlockHero3 />, <coinPrice0 />, dst.) dan atribut sign="" juga dikosongkan.
- Laporan crash (Xiaomi M2003J15SC, Android 10, ARMv7) menunjukkan SIGSEGV saat
  GameActivity baru dibuka, TEPAT setelah log `locale=id`:
      Fatal signal 11, fault addr 0x18, "Cause: null pointer dereference"
      #00 libgame.so  DHValue::getValue() const+2
  Instruksi di +2 adalah `ldr r3,[r1]` dengan r1 = 0x18 -> argumen `this` DHValue
  bernilai 0x18 (null + offset anggota 0x18). Artinya pemanggil mengambil
  anggota dari objek NULL lalu memanggil getValue(). Itu terjadi saat
  PriceManager membaca node harga (rookieGifts%d0, coinPrice%d, unlockHero%d,
  heroPackGift, gearPackGift, christmas%d, atribut `sign`) yang tidak punya isi.
- Bukti pendukung: price.xml SATU-SATUNYA file config dengan elemen kosong (23)
  dan atribut kosong (1); 10 file config lain 0 elemen/atribut kosong. Crash
  muncul berulang di setiap pembukaan game, bukan di tengah permainan.

PERBAIKAN:
- Setiap elemen di <dollar><cn> diberi teks "0" dan sign diberi "Rp".
- Tidak ada pembayaran uang nyata: jalur bayar tunai tetap dimatikan oleh
  patch_barter_native.py; nilai "0" hanya agar node punya isi (tidak null).
- Idempotent: dijalankan ulang tidak mengubah apa pun.
- Format file dijaga persis seperti aslinya: 4 byte panjang (big-endian,
  ukuran XML setelah dekompresi) + aliran zlib.
"""
from __future__ import annotations

import os
import re
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRICE = os.path.join(
    ROOT, "kingdom-in-chaos-decompiled", "assets", "public", "config", "price.xml"
)

NILAI_HARGA = "0"      # teks pengisi agar node tidak null
TANDA_MATA_UANG = "Rp"  # pengganti sign="" (atribut kosong)


def perbaiki(xml: str) -> str:
    # 1) Isi atribut sign yang kosong.
    xml = xml.replace('<cn sign="">', '<cn sign="%s">' % TANDA_MATA_UANG)

    # 2) Isi semua elemen kosong di dalam <dollar>...</dollar> (hanya blok ini).
    m = re.search(r"<dollar>.*?</dollar>", xml, flags=re.DOTALL)
    if not m:
        raise RuntimeError("Blok <dollar> tidak ditemukan di price.xml")
    blok = m.group(0)
    blok_baru = re.sub(
        r"<([A-Za-z_]\w*)\s*/>",
        lambda x: "<%s>%s</%s>" % (x.group(1), NILAI_HARGA, x.group(1)),
        blok,
    )
    return xml[:m.start()] + blok_baru + xml[m.end():]


def main() -> None:
    with open(PRICE, "rb") as f:
        raw = f.read()
    xml = zlib.decompress(raw[4:]).decode("utf-8")
    baru = perbaiki(xml)
    if baru == xml:
        print("price.xml sudah diperbaiki (tidak ada perubahan).")
        return
    data = baru.encode("utf-8")
    with open(PRICE, "wb") as f:
        f.write(struct.pack(">I", len(data)) + zlib.compress(data, 9))
    print("price.xml diperbaiki: elemen dolar kosong diisi, sign diisi.")


if __name__ == "__main__":
    main()
