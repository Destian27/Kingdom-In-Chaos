# CHANGELOG — v17.14.7 Signing Fix

Masalah: APK gagal dipasang, "Aplikasi tidak terinstal". Penyebab: tanpa secret `KEYSTORE_BASE64`, tiap build
GitHub Actions membuat keystore baru, sehingga tanda tangan beda dengan versi yang sudah terpasang.

Perbaikan:
- `keystore/dtp-fixed.keystore` ditambahkan (alias `kingdomchaosdtp`, password `android123`).
- Workflow memakai keystore ini otomatis bila secret `KEYSTORE_BASE64` kosong.
- `.gitignore` mengecualikan keystore ini dari aturan `*.keystore`.

Langkah satu kali: uninstall versi lama (tanda tangannya beda), lalu pasang APK dari build ini.
Setelah itu semua update bisa menimpa tanpa uninstall.
Catatan: repo publik, jadi keystore ini bisa dipakai siapa saja untuk menandatangani APK. Untuk lebih aman, pakai secret.
