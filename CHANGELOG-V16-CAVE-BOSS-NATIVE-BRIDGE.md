# Kingdom In Chaos DTP — v16 Native Runtime Bridge + Cave Boss Admin

Tanggal: 26 November 2026

## Perubahan yang digabung

- Panel `admin.html` diganti dengan panel v16 Cave Boss Hourly; Edge Function `supabase/functions/game-admin/index.ts` diganti dengan TypeScript v16.
- SQL lengkap v16 menggabungkan backend v15, strict maintenance gate, admin player economy, dan Cave Boss hourly schedule / manual override.
- Cave Boss menggunakan waktu WIB (`Asia/Jakarta`), RPC `get_active_cave_boss()`, jadwal 24 jam, manual override, log audit, dan pembacaan authenticated.
- Android membaca snapshot ekonomi via `get_my_game_runtime_state()` dan event Cave Boss via `get_active_cave_boss()`.
- JNI bridge menargetkan `libgame.so` 32-bit yang dibundel: Coins, Crystals, dan Goblin Coins melalui fungsi native `LevelManager`/wallet yang diekspor. Pemanggilan dijalankan pada Cocos `GLSurfaceView` thread.
- Revisi timestamp per mata uang dibuat hanya saat admin mengubah kolom terkait. Saldo lokal lama tidak ditimpa default 0, dan revisi yang sudah diterapkan disimpan per akun Supabase Auth.
- Build script kini mengompilasi `dtp/native/game_runtime_bridge.cpp` untuk `armeabi-v7a`; GitHub Actions memasang NDK `27.2.12479018`.

## Batas integrasi yang harus dipahami

- JNI hanya menghubungkan tiga mata uang native di atas. XP, level, energy, stamina, honor, arena tokens, skill points, extra stats, profil/avatar, cloud save, PvP, dan World Boss masih tidak diubah ke dalam gameplay native.
- RPC Cave Boss sudah dibaca oleh aplikasi dan statusnya ditampilkan sebagai banner di atas game. Ini BELUM memunculkan musuh, scene gua, AI, HP aktual, serangan, loot, atau pertarungan Boss. Source native C++ dan asset/scene Cave Boss tidak ditemukan dalam ZIP v15 yang diterima.
- Native functions yang dijadikan sasaran cocok dengan exported symbols di `lib/armeabi-v7a/libgame.so`, tetapi JNI bridge belum dikompilasi dengan Android NDK dan belum diuji di APK/perangkat dalam sesi ini. Build APK dan uji runtime masih wajib.
- Native balance dibatasi `INT_MAX` (2.147.483.647) sesuai fungsi native yang menerima `int`; SQL menolak angka yang melampaui batas ini untuk tiga mata uang tersebut.
- SQL dan Edge Function belum dideploy ke proyek Supabase pengguna. Menggabungkan file ZIP tidak otomatis mengubah server Supabase yang sudah berjalan.

## Deploy

### Proyek baru / pemasangan lengkap

Jalankan `supabase/kingdom-in-chaos-dtp-SQL-SUPER-LENGKAP-ALL-IN-ONE-v16-CAVE-BOSS-NATIVE-BRIDGE.sql` di Supabase SQL Editor sebagai project owner.

### Proyek yang sudah menggunakan v15

Jalankan berurutan:

1. `supabase/migrations/202611260004_cave_boss_v16.sql`
2. `supabase/migrations/202611260005_native_economy_revision_bridge_v16.sql`

Deploy ulang Edge Function `game-admin` dari `supabase/functions/game-admin/index.ts`. Pertahankan `SUPABASE_SERVICE_ROLE_KEY` hanya sebagai secret server/Edge Function; jangan masukkan ke HTML atau APK.

### Build APK

Butuh JDK 17+, Android SDK platform 35, build-tools 35.0.0, Android NDK 27.2.12479018, serta `tools/apktool.jar`. GitHub Actions workflow sudah memasang platform/build-tools/NDK dan mengunggah artifact APK.

Build lokal:

```bash
python3 -m pytest -q tests
python3 build_dtp.py
```

Simpan keystore yang sama untuk mempertahankan signature APK saat update di atas instalasi yang sudah ada.

## Uji wajib setelah build

1. Pasang APK ke akun uji yang memiliki saldo lokal lama; pastikan saldo tidak berubah saat tidak ada admin revision.
2. Ubah hanya Coins via Admin; pastikan hanya Coins yang berubah dalam game.
3. Ubah Crystals dan Goblin Coins secara terpisah; pastikan saldo lain tetap.
4. Keluar/masuk game dan akun lain pada perangkat yang sama; pastikan revision tidak tertukar antar-user.
5. Aktifkan jadwal Boss Gua; pastikan banner status tampil dan hilang saat jadwal tidak aktif.
6. Uji maintenance, Realtime, dan admin audit di proyek Supabase staging sebelum produksi.
