# Kingdom in Chaos DTP — SQL Super Lengkap v14 (Realtime-ready)

## Paket ini
- `kingdom-in-chaos-dtp-SQL-SUPER-LENGKAP-ALL-IN-ONE-v14-REALTIME.sql`: SQL gabungan v13 dengan penguatan Realtime, RLS baca ekonomi milik sendiri, antrean PvP pribadi, RPC runtime state, dan RPC atomik admin ekonomi + audit. Juga menghapus satu baris backslash liar yang dapat membuat SQL Editor gagal.
- `kingdom-in-chaos-dtp-game-admin-function-v12-realtime.ts`: Edge Function admin yang memakai RPC atomik agar perubahan ekonomi dan audit tercatat dalam transaksi yang sama.
- `kingdom-in-chaos-dtp-client-realtime-reference-v14.ts`: contoh subscription Supabase Realtime untuk klien TypeScript/web.
- `kingdom-in-chaos-dtp-SupabaseGameBackend-v14.java`: adapter Java dengan `getMyRuntimeState()` untuk mengambil snapshot REST ketika login/resume.

## Cara memasang
1. Cadangkan proyek Supabase dan periksa SQL dahulu sebelum eksekusi. File lengkap ini memuat SQL fondasi + migrasi sebelumnya, jadi gunakan pada proyek yang sesuai dan baca error SQL pertama jika ada. Jangan menjalankan potongan fondasi berulang secara membabi buta pada database yang memiliki skema kustom.
2. Edit placeholder `GANTI_EMAIL_ADMIN_ANDA` menjadi email akun Auth yang sudah ada jika perlu bootstrap admin.
3. Jalankan di Dashboard → SQL Editor. Pastikan query verifikasi menampilkan publication `supabase_realtime` serta fungsi `admin_update_player_economy` dan `get_my_game_runtime_state`.
4. Ganti Edge Function `game-admin` dengan file TS v12 lalu deploy: `supabase functions deploy game-admin`. Secret `SUPABASE_SERVICE_ROLE_KEY` hanya di server function, jangan di APK/HTML.
5. Klien game harus subscribe ke `game_admin_player_economy` dengan filter `user_id` miliknya sendiri. Web/TS bisa menggunakan contoh yang tersedia. Native Android Java perlu implementasi WebSocket/Supabase Realtime tersendiri; method Java yang disertakan hanya mengambil snapshot REST.

## Apakah ini 100% realtime dan berdampak langsung?
Belum untuk game native. SQL v14 mengaktifkan publication untuk tabel player-facing, mengizinkan pemain membaca row ekonominya sendiri, dan memastikan pembaruan ekonomi admin menghasilkan perubahan database + audit atomik. TS Edge Function mengirim perubahan ke database. Klien yang benar-benar subscribe akan menerima event.

Tetapi adapter Java contoh belum membuka subscription WebSocket dan game native belum memetakan `coins`, `crystals`, `hero_xp`, dll. ke format save asli di `libgame.so`. Karena itu perubahan admin saat ini berdampak langsung pada database backend; dampak pada nilai yang dilihat/ditampilkan gameplay baru terjadi setelah subscription klien dan integrasi native save diterapkan dan diuji. SQL tidak menjalankan PvP native ataupun validasi otomatis World Boss.

Jangan menaruh `service_role` dalam APK atau HTML. Migrasi dan function belum diterapkan ke proyek pengguna; perlu deploy dan uji dengan dua akun.
