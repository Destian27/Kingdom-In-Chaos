# CHANGELOG — v17.8 Hero Stack Fix

Tanggal: 27 November 2026
Masalah: game keluar sendiri saat tombol **MULAI** ditekan. Penyebab ditemukan dari laporan crash v17.7.

## Penyebab 1 (utama, native): stack corruption di `UserDataManager::getHeroGearInfo`
Log: `stack corruption detected (-fstack-protector)` → `__stack_chk_fail` ← `getHeroGearInfo(int, GearPartType)+200`.

- `getHeroGearInfo` memanggil `UserDataManager::isHeroUnlock(int)` (`0x2E17DC`).
- Patch null-guard `CCTexture2D::hasPremultipliedAlpha` menaruh kode trampolinnya di `0x2E17E0`.
  Saat `isHeroUnlock` masih berupa stub `movs r0,#1; bx lr`, area itu memang kode mati.
  Setelah alur beli hero dikembalikan ke aslinya (v17.x), `0x2E17E0` ternyata badan fungsi asli:
  prolog `push {r4-r6,lr}; sub sp,#16` tetap jalan, lalu trampolin langsung `bx lr` tanpa
  memulihkan SP/LR → SP pemanggil bergeser 32 byte → canary rusak → SIGABRT di GLThread.
- Perbaikan di `libgame.so` (armeabi dan armeabi-v7a):
  - Badan `isHeroUnlock` dipulihkan di `0x2E17E0..0x2E17E9`
    (`movs r3,#0; adds r4,r1,#0; add r1,sp,#4; str r3,[sp,#4]; str r3,[sp,#8]`),
    direkonstruksi dari fungsi kembarnya `0x2E1770` yang memakai pola identik.
  - Trampolin `hasPremultipliedAlpha` dipindah ke ekor mati `TestinAgentHelper::initTestinAgent(char const*, char const*)`
    (`0x441CC0` = `bx lr`, `0x441CC4`), dan `b.w` di `0x484472` diarahkan ke sana.

## Penyebab 2 (Java): `NetworkOnMainThreadException`
Log: `MaintenanceActivity.onPause → stopRt → RealtimeClient.stop → closeQuietly → SSLSocket.close`.
- `RealtimeClient.stop()` kini menutup socket di thread latar (`closeAsync`, thread `kic-realtime-close`),
  bukan di thread pemanggil. `closeQuietly` menangkap `Throwable`.

## Lain-lain
- `build_apk.py`: `patch_map` diselaraskan dengan biner terkirim (stub `isHeroUnlock`/`payUnlockHero` dan injeksi
  mata uang dihapus, trampolin dipindah). Sebelumnya skrip ini bisa menghasilkan ulang biner yang rusak.
- Tes baru: `test_fix15b_is_hero_unlock_body_intact`, `test_realtime_stop_never_closes_socket_on_caller_thread`;
  `test_fix15` diperbarui ke lokasi trampolin baru.

## Batasan yang diketahui
- APK belum dikompilasi dan belum diuji di perangkat dalam sesi ini (tidak ada Android SDK/NDK di lingkungan ini).
- Sepuluh byte asli `isHeroUnlock` direkonstruksi (bukan disalin dari `libgame.so` asli, yang tidak ada di zip).
  Secara fungsi setara dengan fungsi kembarnya; bila crash tetap muncul, kirim laporan crash baru lewat tombol LAPORAN CRASH.
