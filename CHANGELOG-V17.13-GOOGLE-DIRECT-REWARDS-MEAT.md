# Kingdom In Chaos DTP v17.13 — Google Direct Auth, Kode Hadiah, dan Daging

## Autentikasi pemain
- Overlay akun memakai ikon Google dan membuka pemilih akun Google Android.
- Pemain tidak menggunakan Supabase Auth, email/password game, atau konfirmasi password.
- Google access token diverifikasi oleh Edge Function memakai Google OpenID userinfo; akun ditolak kecuali `email_verified=true`.
- Pemain baru diarahkan ke Tahap 2 untuk membuat nickname 3–32 karakter. `player_id` numerik unik dibuat server saat identitas Google pertama kali terdaftar.
- Sesi Google menyimpan nama akun pada private preferences; access token tidak disimpan. Token diminta kembali melalui Google Play Services ketika diperlukan.

## Admin
- Admin HTML menampilkan semua pemain Google secara otomatis tanpa input pencarian, termasuk email, avatar, ID, nickname, Koin, DM, daging, verifikasi, dan tanggal pendaftaran.
- Admin dapat membuat kode hadiah, menyalin kode, menentukan reward Koin/DM/Goblin Coin/Daging, kuota klaim, waktu aktif, serta menonaktifkan/mengaktifkan kode.
- Akun admin tetap masuk melalui Supabase Auth terpisah. Ini bukan login pemain.

## Kode hadiah
- Kode 4–40 karakter, A–Z/angka/tanda hubung.
- Setiap akun Google dapat mengklaim kode yang sama satu kali.
- Kuota global, masa berlaku, status aktif, dan reward disimpan di database.

## Makanan native (energi misi)
- Game asli sudah memiliki sistem Makanan/Life native dengan kapasitas 24 dan biaya 1 makanan pada battle normal (`battleLifeCost=1`). Sistem asli juga memiliki pembelian makanan melalui panel native.
- Konfigurasi `lifeRecoveryInterval` di `assets/public/config/price.xml` diubah dari 1.200 detik menjadi 300 detik (1 makanan setiap 5 menit).
- Nilai pembelian native yang sudah ada tidak diubah: `buyLifeNum=12` dan `buyLifeCost=50`. Mata uang/flow pembelian tetap memakai mekanisme native game, bukan transaksi uang asli.

## Daging Cloud untuk admin/reward
- Akun Google juga memiliki kolom daging cloud terpisah untuk hadiah kode dan tampilan admin; kapasitas default 24 dan regenerasi server +1 setiap 300 detik.
- Harga default pembelian di wallet cloud: 1 DM per 1 daging; dapat diubah di `public.game_meat_config`.
- Layar Daging Cloud memuat state server, membeli daging, dan mengurangi satu daging melalui RPC.
- Daging Cloud belum disinkronkan dengan Makanan/Life native. Untuk memulai stage, sumber daya yang dipakai tetap Makanan/Life native milik game.

## Deployment
1. Jalankan `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.13-GOOGLE-AUTH-KODE-DAGING.sql` di Supabase SQL Editor. File ini menggabungkan SQL v17.4 yang pengguna kirim dan migrasi tambahan v17.13.
2. Deploy `supabase/functions/google-player/index.ts` sebagai function `google-player`.
3. Deploy `supabase/functions/game-admin/index.ts` sebagai function `game-admin`. Pastikan `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY` tersedia pada server function.
4. Set `GOOGLE_OAUTH_CLIENT_ID` pada `google-player` ke Android OAuth client ID yang terdaftar untuk package `com.destian.kingdominchaosdtp` dan SHA-1 dari signing keystore yang dipakai build.
5. Host `admin.html` melalui HTTPS. Login admin tetap menggunakan admin Supabase Auth yang terdaftar pada `game_admin_users`.
6. Gunakan signing keystore yang sama secara persisten pada setiap build GitHub Actions; simpan bytes-nya di secret `KEYSTORE_BASE64`, berikut `KEYSTORE_PASS` dan `KEYSTORE_ALIAS`. SHA-1 Android OAuth harus cocok dengan keystore itu.

## Batasan yang harus diketahui
- Sumber C++ / scene asli tidak tersedia. Paket mengandalkan gate dan konsumsi Makanan/Life bawaan `libgame.so`, serta hanya mengubah konfigurasi recovery menjadi 300 detik. Nilai ini perlu dikonfirmasi pada pengujian runtime APK.
- Koin/DM native di `libgame.so` dan wallet cloud Google masih dua tempat terpisah. Nilai DM/Koin pada daftar admin adalah wallet cloud `game_google_player_economy`, belum otomatis disinkronkan dari saldo asli game. Daging Cloud juga terpisah dari Life native.
- Google token retrieval memakai Google Play Services `GoogleAuthUtil` melalui reflection. Keberhasilan runtime masih perlu diuji pada APK bertanda tangan dengan package/SHA-1 OAuth yang cocok.
- APK tidak dibangun atau diuji di perangkat pada lingkungan ini karena Android SDK/NDK/apktool tidak tersedia. ZIP berisi source/patch dan workflow GitHub Actions.
