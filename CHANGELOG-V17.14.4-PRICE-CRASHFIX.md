# CHANGELOG — v17.14.4 Price Crash Fix

Tanggal: 27 November 2026
Basis: v17.14.3 (APK terakhir yang dilaporkan: 17.14.2, versionCode 12)
Masalah: game keluar sendiri setiap kali dibuka (layar MaintenanceActivity -> GameActivity).

## Bukti dari laporan crash (Xiaomi M2003J15SC, Android 10, ARMv7)
```
Fatal signal 11 (SIGSEGV), fault addr 0x18, Cause: null pointer dereference
#00 libgame.so  DHValue::getValue() const+2
```
- Crash berulang 8x berturut-turut di setiap peluncuran, tepat setelah log `be: locale=id`
  (saat konfigurasi dimuat), bukan di tengah permainan.
- `getValue()+2` adalah `ldr r3,[r1]` dengan `r1 = 0x18`: `this` = NULL + offset anggota 0x18.
  Pemanggil mengambil anggota dari node NULL lalu memanggil `getValue()`.

## Penyebab
- v17.12 mengosongkan harga dolar di `price.xml` (`<unlockHero3 />`, `<coinPrice0 />`, ... 23 elemen)
  dan atribut `sign=""`. `PriceManager` membaca node itu lewat nama (`unlockHero%d`, `coinPrice%d`,
  `crystalPrice%d`, `rookieGifts%d0`, `heroPackGift`, `gearPackGift`, `christmas%d`, `sign`)
  -> node tanpa isi menghasilkan objek NULL -> SIGSEGV.
- Pendukung: `price.xml` adalah SATU-SATUNYA dari 11 file config yang punya elemen/atribut kosong.

## Perbaikan
- `tools/patch_price_dollar_fix.py` (baru, idempotent): isi semua elemen di `<dollar><cn>` dengan `0`
  dan `sign="Rp"`. Format file dijaga (header panjang big-endian + zlib).
- `build_dtp.py` memanggil patch ini sebelum build; `price.xml` di sumber juga sudah dipatch.
- Pembayaran uang nyata tetap nonaktif (patch barter native tidak diubah). Nilai `0` hanya pengisi.
- Versi: `versionName 17.14.4`, `versionCode 13`, output `KingdomInChaosDTP-v17.14.4-price-crashfix.apk`.
- Tes baru `tests/test_v17_14_4_price_crashfix.py`; tes lama diselaraskan. Hasil: 101 lulus, 2 dilewati.

## Batasan
- APK belum dikompilasi/diuji di perangkat di lingkungan ini (tidak ada SDK/NDK/apktool).
- Penyebab ditentukan dari backtrace + disassembly manual Thumb + pola config, bukan dari reproduksi.
  Bila crash tetap muncul dengan backtrace yang sama, kirim laporan baru (lihat frame #01 pemanggil).
