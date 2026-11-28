# CHANGELOG — v1.0.6 Install Fix

- versionName `1.0.6` (sebelumnya 17.14.8) — tampil di Info Aplikasi.
- versionCode `106` (sebelumnya 16). Android menolak "downgrade", jadi versionCode harus lebih besar dari
  yang terpasang (16) agar APK baru bisa menimpa tanpa gagal instal. Naikkan lagi (107, 108, ...) untuk update berikutnya.
- Tanda tangan tetap `keystore/dtp-fixed.keystore` (alias `kingdomchaosdtp`) — jangan diganti, supaya update menimpa.
- Output APK: `KingdomInChaosDTP-v1.0.6.apk` (build_dtp.py + workflow GitHub Actions).
- Tidak ada perubahan SQL / Edge Function / admin.
