# CHANGELOG — v17.14.8 Price/Barter Crash Fix

Tanggal: 27 November 2026 | Basis: v17.14.6 (+ signing fix) | versionCode 16

## Bug: game keluar sendiri sebelum menu muncul
Laporan 27 Nov 2026 19:43 (Xiaomi M2003J15SC, Android 10, v17.14.6): SIGSEGV, fault addr 0x0, thread GLThread.
```
#01 libgame.so PriceManager::loadGameValue(tinyxml2::XMLElement*, std::map&)+44   (0x2B85C5)
#02 PriceManager::loadPrice()+110
#05 PreloadLayer::update(float)
```
Disassembly Thumb `loadGameValue` (0x2B8598): untuk setiap elemen saudara setelah `<dollar>` ia memanggil
`tinyxml2::XMLElement::GetText()` lalu memakai hasilnya langsung sebagai string. Elemen tanpa node teks
mengembalikan NULL -> crash. `loadPrice` memanggil `loadGameValue` pada elemen setelah `<dollar>`.

## Penyebab
`price.xml` (sejak v17.12) berisi blok `<barter>` di akhir file, berisi elemen anak (`<coinPack0 ... />`) tanpa teks.
`GetText()` pada `<barter>` = NULL -> SIGSEGV di PreloadLayer, setiap kali game dibuka.

## Perbaikan
- `tools/patch_price_dollar_fix.py`: blok `<barter>` dikeluarkan dari `price.xml` dan disimpan di
  `assets/dtp_barter_prices.json` (hanya rujukan; kode barter memakai nilai di bridge native/Java). Idempotent.
  Semua elemen selain `<dollar>` kini punya teks.
- Tombol overlay **GOOGLE**, **SURAT**, **BARTER** dihapus dari layar (fiturnya sudah ada di game).
- Login Google: pemilih akun langsung muncul (sekali per proses) bila belum ada akun tertaut; `GameAuthActivity`
  membuka pemilih akun otomatis. Setelah login, alur lama ke Hub Online/Profil tetap berjalan.
- Versi: `versionName 17.14.8`, `versionCode 16`, output `KingdomInChaosDTP-v17.14.8-price-barter-crashfix.apk`.
- Tes baru `tests/test_v17_14_8_price_barter_crashfix.py`; tes lama diselaraskan.

## Batasan
- APK belum dibuild/diuji di perangkat (tidak ada SDK/NDK/apktool di sini). Penyebab ditentukan dari backtrace +
  disassembly manual `loadGameValue`/`loadPrice`. Jika crash tetap ada, kirim laporan baru.

## Tambahan (screenshot 27 Nov 2026)
- Game sudah terbuka normal. Area sentuh tak terlihat (`GameOnlineOverlay.Hotspots`) dipasang di atas tombol bawaan game:
  - **LOGIN** (kiri atas) -> pemilih akun Google (`GameAuthActivity`); bila sudah login -> Hub Online.
  - **Bakat** (menu kanan, di bawah Surat) -> Hub Online: Surat hadiah admin, Kode Hadiah, Daging. Belum login -> login Google dulu.
  - Tombol **Surat** bawaan game tidak diubah.
- Pemilih akun otomatis saat game dibuka dihapus (diganti tombol LOGIN).
- File server: `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.14.8.sql`, `...game-admin-function-v17.14.8.ts`,
  `...google-player-function-v17.14.8.ts` (isi sama dengan v17.14.2/v17.14.3 + penanda versi; tidak ada perubahan skema).
- Koordinat area sentuh diukur dari screenshot (Xiaomi M2003J15SC, relatif terhadap tinggi layar); di perangkat dengan
  rasio layar sangat berbeda posisi bisa meleset. Fungsi asli Bakat (talent) tidak bisa dibuka lagi.
