# CHANGELOG — v17.11 Money Button Crash Fix

Tanggal: 27 November 2026
Basis: v17.10 (dialog wrap Bahasa Indonesia)
Masalah: game keluar sendiri beberapa detik setelah masuk peta (saat tutorial awal dimulai).

## Penyebab (dari laporan crash v17.9, Xiaomi M2003J15SC, Android 10)
```
Fatal signal 11 (SIGSEGV), fault addr 0x656e6566, GLThread
#01 UIFloatingWindow::setAllEnabled(bool)+156
#02 UIFloatingWindow::onNotificationAllBtnEnabled
#05 UIMapLayer::beginTutorialStory()
```
- `pc = 0x656e6566` adalah teks ASCII, bukan alamat kode: `blx r3` memanggil fungsi virtual lewat objek yang sudah dibebaskan.
- Objeknya adalah tombol uang (Top Up) di `UIFloatingWindow+0x12C`, blok ke-7 di `setAllEnabled`.
- Fix 17 (Top Up disembunyikan) menghapus `addChild` tombol itu di `initMoneyInfo` (`0x35769E`).
  Tombol dibuat lewat `create()` (autorelease) dan tidak pernah di-retain, jadi dibebaskan di akhir frame,
  sementara pointer di `this+0x12C` tetap tersimpan. Tutorial peta memanggil `setAllEnabled` -> crash.
- Pengguna lama yang tidak memicu tutorial tidak melihat crash, tetapi `getMoneyStorePosition`, `setStoreVisible`,
  `setStoreEnabled`, `setAllvisible` memakai pointer yang sama dan berisiko yang sama.

## Perbaikan (libgame.so, armeabi dan armeabi-v7a)
- `0x357698..0x35769F`: pemanggilan virtual `addChild` yang sudah dihapus diganti inline `CCObject::retain` pada tombol uang:
  `ldr r3,[r1,#12]; adds r3,#1; str r3,[r1,#12]; nop` (offset `m_uReference` = 12 dikonfirmasi dari `CCObject::retain` di `0x454A60`).
- Tombol tetap tidak ditambahkan ke layar (Top Up tetap tersembunyi, `onBank` tetap `bx lr`), tetapi objek hidup terus,
  sehingga semua pemakai `this+0x12C` aman. Biayanya satu objek kecil per instance `UIFloatingWindow`.
- `build_apk.py`: patch_map dilengkapi (patch ini dan `onBank`), supaya biner hasil regenerasi sama dengan yang dikirim.
- Tes baru: `test_fix18_money_button_retained_no_dangling_pointer`.
- Versi: `versionName 17.11`, `versionCode 8`, output `KingdomInChaosDTP-v17.11.apk`.

## Batasan
- APK belum dikompilasi dan belum diuji di perangkat (tidak ada Android SDK/NDK/apktool di lingkungan ini).
  Patch biner diverifikasi dengan membaca instruksi Thumb secara manual dan dengan tes byte.
- Bila game masih keluar sendiri, kirim laporan crash baru (ikon `!` / LAPORAN CRASH).
