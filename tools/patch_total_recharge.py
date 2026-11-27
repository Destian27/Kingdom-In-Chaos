#!/usr/bin/env python3
"""v17.14.12 — ambang Total Recharge (layar Penawaran) memakai nominal DM.

PriceManager::addFirstAddUpGift() (@0x2BDE68) memuat empat float ambang dari
kolam literal @0x2BE208..0x2BE214. Nilai asli 20/50/150/500 (dolar) diganti
40/100/300/1000 (DM): puncak 1.000 DM = semua hadiah bisa diklaim.

Progres bertambah lewat PriceManager::handlePaidOK(), yang menjumlahkan harga
item (price.xml, sekarang dalam DM) setiap pembelian barter berhasil.
Idempoten; hanya data float (tanpa mengubah instruksi).
"""
import os, struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OFFSETS = (0x2BE208, 0x2BE20C, 0x2BE210, 0x2BE214)
ASLI = (20.0, 50.0, 150.0, 500.0)
BARU = (40.0, 100.0, 300.0, 1000.0)


def main():
    for abi in ("armeabi", "armeabi-v7a"):
        p = os.path.join(ROOT, "kingdom-in-chaos-decompiled", "lib", abi, "libgame.so")
        d = bytearray(open(p, "rb").read())
        now = tuple(struct.unpack_from("<f", d, o)[0] for o in OFFSETS)
        if now == BARU:
            print(abi, ": ambang sudah", BARU)
            continue
        if now != ASLI:
            raise RuntimeError("%s: nilai tak terduga %r" % (abi, now))
        for o, v in zip(OFFSETS, BARU):
            struct.pack_into("<f", d, o, v)
        open(p, "wb").write(d)
        print(abi, ": ambang", ASLI, "->", BARU)


if __name__ == "__main__":
    main()
