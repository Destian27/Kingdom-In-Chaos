# Kingdom in Chaos DTP — Admin Data Pemain v11

Panel `admin.html` kini mempertahankan fitur maintenance yang lama dan menambahkan halaman **Manajemen Data Pemain**. Akses panel data pemain memakai Supabase Auth dan harus ditandai sebagai admin dalam `public.game_admin_users`.

## Yang dapat dilihat

- Identitas Auth yang aman untuk ditampilkan: user ID, email, status konfirmasi email/telepon, tanggal dibuat/diubah, login terakhir, status ban jika ada, metadata user dan metadata app. Password hash, password, access token, refresh token dan confirmation token tidak pernah dikirim ke browser.
- Profil game: username, nickname, Avatar ID dan region.
- Status online/last seen, statistik ranking, riwayat versi cloud save dan payload save cloud JSON.
- Coins, Crystals, Goblin Coins, XP hero, level hero, XP/level pemain, energy, stamina, honor points, arena tokens, skill points dan statistik tambahan JSON.
- Audit log perubahan admin dengan admin ID, user sasaran, alasan serta ringkasan sebelum/sesudah.

## Pemasangan

1. Pastikan migration backend online v10 sudah dipasang pada proyek Supabase yang digunakan DTP.
2. Buka `supabase/migrations/202611260003_admin_player_management.sql` pada SQL Editor Supabase, lalu jalankan sekali.
3. Pastikan email admin sudah mempunyai akun di Authentication → Users. Kalau belum ada, buat akun admin terlebih dahulu melalui alur pendaftaran yang sesuai dengan kebijakan proyek.
4. Buka `supabase/admin-bootstrap.sql`, ganti `YOUR_ADMIN_EMAIL` dengan email admin yang tepat, lalu jalankan. Periksa hasil query verifikasi; harus ada akun tersebut dengan `role = super_admin` dan `active = true`.
5. Deploy function dengan Supabase CLI dari direktori proyek:

   ```sh
   supabase functions deploy game-admin
   ```

   Edge runtime harus memiliki environment `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY`. Supabase biasanya menyediakan nilai proyek untuk function; periksa konfigurasi proyek sebelum deploy. **Jangan memasukkan service-role key ke `admin.html`, APK, atau repository publik.**
6. Hosting `admin.html` sebagai halaman admin statis melalui hosting HTTPS. Maintenance lama tetap menggunakan endpoint `maintenance-admin` yang sudah ada; halaman manajemen pemain memakai endpoint baru `game-admin` dan login Supabase Auth tersendiri.
7. Buka panel, masuk dengan kredensial admin maintenance untuk maintenance jika dibutuhkan. Pilih **Manajemen Data Pemain**, lalu masuk lagi menggunakan email/password akun Supabase yang tadi di-whitelist. Jika ditolak, periksa row `game_admin_users`, deployment function dan secret proyek.

## Catatan integrasi penting

Migration menyiapkan tabel `game_admin_player_economy` sebagai **kolom statistik yang dikelola admin di backend**. Baris akun lama dibuat dengan nilai awal `0`; nilainya tidak diimpor otomatis dari native save karena struktur asli belum dipetakan. Ini membuat panel dapat menyimpan nilai Coins/Crystals/Goblin Coins/XP dan statistik lain, tetapi tidak boleh dianggap otomatis mengubah mata uang di save lokal asli yang tertanam pada game native. Source v10 yang tersedia belum menyediakan kode native lengkap untuk membaca/menulis format save asli di `libgame.so`; perlu integrasi lanjutan sebelum perubahan backend tersebut benar-benar tercermin di semua layar game.

Begitu pula, JSON yang diedit di bagian “Save cloud lengkap” adalah `public.game_player_saves.save_data` milik Supabase; bukan jaminan bahwa save lokal native berubah. Jangan mengedit JSON jika belum memahami format aplikasi yang mengirimkannya. Perubahan save dicatat melalui trigger history yang sudah disediakan backend v10, jika trigger migration sebelumnya telah dipasang.

## Keamanan

- Tabel `game_admin_users`, `game_admin_player_economy`, dan `game_admin_audit` tidak dapat dibaca langsung oleh `anon` atau `authenticated`. Browser harus melewati Edge Function.
- Edge Function memverifikasi access token melalui Supabase Auth lalu memeriksa admin aktif di tabel private.
- Setiap perubahan memerlukan alasan 4–500 karakter dan masuk ke audit log.
- Nilai angka divalidasi sebagai non-negatif dan batas BIGINT; field tak dikenal ditolak.
- Fitur ini belum mengedit alamat email/password akun Auth atau melakukan ban/unban. Itu di luar fungsi yang ditambahkan di versi ini.


## Pembaruan v16 — catatan yang menggantikan batasan awal

Dokumen ini menjelaskan kondisi saat admin v11/v15 dibuat. Pada paket v16, JNI bridge menambahkan penerapan langsung ke wallet native untuk Coins, Crystals, dan Goblin Coins saja. Revisi tiap field membuat saldo lokal lama tidak tersentuh sampai admin mengubah mata uang tersebut. XP, level, energy/stamina, honor, arena, skill point, extra stats, dan sinkronisasi save penuh tetap belum terhubung ke native gameplay. Lihat `CHANGELOG-V16-CAVE-BOSS-NATIVE-BRIDGE.md` untuk instalasi SQL v16, build NDK, serta uji perangkat yang diperlukan.
