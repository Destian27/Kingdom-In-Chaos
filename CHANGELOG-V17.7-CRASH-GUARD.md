# CHANGELOG — v17.7 Crash Guard

Tanggal: 27 November 2026
Masalah: game keluar sendiri saat tombol **MULAI** ditekan di layar judul.

## Temuan audit (sumber v17.6)
- Semua 41 tes sumber bawaan lulus; tidak ada regresi yang tertangkap tes.
- Jalur Java DTP untuk pemain yang belum login (cek maintenance, realtime, polling event store,
  overlay LOGIN) tidak mengandung bug deterministik yang menutup game saat MULAI.
- Pemeriksaan JNI: semua kelas Java yang dipanggil native ada di smali, kecuali
  `com/umeng/cocos2dxsdkhelper/ThreadHelper` (jalur Umeng yang sudah dinonaktifkan di native).
  `AdMgr` dan `CrossPromotionUtil` aman walau init dimatikan (dijaga flag `_init`).
- Semua file XML konfigurasi (termasuk `de.xml` = terjemahan Indonesia) valid: header panjang
  cocok dengan isi zlib, dan XML terbaca. Beberapa file level/skill/talent memang tidak
  well-formed menurut parser ketat (atribut tanpa spasi), tetapi itu data asli game.
- Penyebab pasti belum bisa dipastikan dari kode sumber saja: `libgame.so` adalah biner hasil
  patch dan tidak ada log crash. Rilis ini menutup celah yang bisa dijaga di sisi Java dan
  merekam penyebabnya dengan tepat jika game masih keluar sendiri.

## Perubahan
- `CrashReporter` (baru): penanda sesi dibuat saat GameActivity tampil dan dihapus saat pause
  normal atau kick maintenance. Jika proses berikutnya menemukan penanda yang tersisa, disusun
  laporan: jejak sesi, alasan keluar menurut Android 11+ (`ApplicationExitInfo`, termasuk
  tombstone native bila ada), dan log relevan dari logcat (FATAL EXCEPTION, Fatal signal,
  JNI DETECTED ERROR, backtrace libgame, tag `be`/`dh`).
- `GameOnlineOverlay`: tombol **LAPORAN CRASH** (di bawah tombol LOGIN) hanya muncul bila ada
  laporan; dialog berisi teks laporan dengan tombol Salin / Hapus / Tutup.
- `DtpApp`: seluruh hook DTP saat GameActivity resume dibungkus `try/catch Throwable` agar
  kode overlay/realtime tidak bisa menjatuhkan game; semua thread latar kini menangkap
  `Throwable` (bukan hanya `Exception`) sehingga `Error` seperti `NoSuchMethodError` atau
  `UnsatisfiedLinkError` tidak mematikan proses.

## Cara memakai
1. Build APK v17.7, pasang, buka game, tekan MULAI sampai game keluar.
2. Buka game lagi: tombol **LAPORAN CRASH** muncul di kiri atas. Tekan, lalu **Salin**.
3. Kirim teks laporan itu untuk menentukan perbaikan akar masalahnya.

## Batasan yang diketahui
- APK belum dikompilasi dan belum diuji di perangkat dalam sesi pengeditan ini.
- Rilis ini tidak mengubah `libgame.so`, smali, aset, atau terjemahan.
- Pada Android 10 ke bawah tidak ada `ApplicationExitInfo`; laporan bergantung pada logcat.
