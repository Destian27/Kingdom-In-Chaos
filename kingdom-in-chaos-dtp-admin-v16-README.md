# Kingdom in Chaos DTP — Admin v16: Boss Gua per Jam

## Isi paket
- `kingdom-in-chaos-dtp-admin-v16.html` — panel admin untuk pengguna + jadwal Boss Gua.
- `kingdom-in-chaos-dtp-game-admin-function-v16-cave-boss.ts` — Edge Function `game-admin` dengan aksi admin Boss Gua.
- `kingdom-in-chaos-dtp-cave-boss-v16-migration.sql` — migrasi tambahan untuk jadwal, override manual, audit, dan RPC runtime.
- `kingdom-in-chaos-dtp-SQL-SUPER-LENGKAP-ALL-IN-ONE-v16-CAVE-BOSS-NATIVE-BRIDGE.sql` — gabungan All-in-One v15, strict maintenance gate, Cave Boss v16, dan revisi wallet native v16.

## Fitur admin
1. Jadwal berulang setiap hari untuk 24 slot, pukul 00.00 sampai 23.00 WIB.
2. Setiap slot dapat diaktif/nonaktifkan, memilih Boss ID dan nama, difficulty, pengali HP, durasi 1–60 menit, dan reward JSON.
3. Boss manual/override dapat dipanggil selama 1–180 menit, lalu jadwal per jam kembali berlaku otomatis.
4. Override bisa dihentikan manual; tindakan disimpan di audit log beserta alasan.
5. Semua penulisan jadwal memakai Edge Function yang memverifikasi sesi Supabase Auth dan tabel `game_admin_users`.
6. RPC `get_active_cave_boss()` memilih boss berdasarkan WIB dan memberikan prioritas ke override manual.

## Instalasi
1. Proyek baru: Supabase Dashboard → SQL Editor, jalankan `supabase/kingdom-in-chaos-dtp-SQL-SUPER-LENGKAP-ALL-IN-ONE-v16-CAVE-BOSS-NATIVE-BRIDGE.sql`. Database v15 yang sudah ada: jalankan berurutan `supabase/migrations/202611260004_cave_boss_v16.sql` lalu `supabase/migrations/202611260005_native_economy_revision_bridge_v16.sql`. Jangan jalankan all-in-one dan migrasi incremental sekaligus.
2. Supabase Dashboard → Edge Functions → function yang bernama `game-admin`: ganti source dengan `kingdom-in-chaos-dtp-game-admin-function-v16-cave-boss.ts`, pastikan secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY` terpasang, lalu deploy.
3. Host file HTML di hosting admin yang sudah dipakai, atau buka file HTML di browser. Panel menggunakan project Supabase `gunzwimrxspbmiducphg` sebagaimana admin v11 sebelumnya.
4. Login melalui panel Admin → Manajemen Data Pemain menggunakan akun Supabase yang sudah memiliki baris aktif di `game_admin_users`.
5. Di bagian “Boss Mode Gua”, isi slot yang diinginkan, lalu Simpan Jadwal 24 Jam.

## Format data
- Boss ID harus identik dengan ID yang dikenali aset/logika game (contoh sintaks: `cave_boss_01`, bukan jaminan bahwa ID contoh tersedia dalam game).
- Reward ditulis sebagai objek JSON, misalnya `{ "coins": 100 }`. Nama field reward harus sesuai dengan integrasi game yang dibuat nanti.
- `difficulty` yang tersedia: `normal`, `hard`, `elite`, `nightmare`, `custom`.
- Pengali HP dibatasi 0,1–10.000; jadwal default berdurasi hingga 60 menit; override manual hingga 180 menit.

## Batas penting — jangan disalahartikan
Android v16 membaca RPC `get_active_cave_boss()` dan menampilkan banner status event di atas gameplay. Ini **belum spawn musuh atau menjalankan pertarungan**: source native C++ dan scene/asset Cave Boss tidak tersedia dalam ZIP v15 yang diberikan, sehingga boss_id/HP/difficulty/reward belum dipetakan ke battle engine. Secara terpisah, JNI bridge v16 menghubungkan Coins, Crystals, dan Goblin Coins ke fungsi wallet native yang diekspor `libgame.so`; hanya mata uang yang diubah admin yang diterapkan, agar saldo lama tidak tertimpa default database. Periksa `CHANGELOG-V16-CAVE-BOSS-NATIVE-BRIDGE.md` untuk cara build dan batas integrasinya. Panel tidak menaruh service-role key di browser/APK.

## Uji setelah deploy
1. Buka Admin, login, dan tekan “Muat Ulang Jadwal”. Harus muncul 24 slot jam.
2. Aktifkan satu slot dan isi ID/nama boss; simpan dengan alasan minimal 4 karakter.
3. Tekan “Panggil Boss Sekarang” dengan durasi singkat, lalu cek status aktif dan audit log.
4. Tekan “Hentikan Override” untuk kembali ke jadwal otomatis.
5. Dari SQL Editor, jalankan `select public.get_active_cave_boss();`. Android menampilkan banner untuk event aktif, bukan battle native.
6. Build APK dari source dengan JDK 17+, Android SDK platform 35, build-tools 35.0.0, NDK 27.2.12479018, dan `tools/apktool.jar`. Kemudian uji perubahan tiap mata uang pada perangkat nyata.
