# v17.14.18 - Bakat diperbaiki, daftar pemain admin tersambung, panel admin dipisah per halaman

## Bakat
- Penyebab: area sentuh tak terlihat `Hotspots` (v17.14.8) menimpa tombol Bakat asli game dan membuka Hub Online / Daging Misi.
- Perbaikan: area Bakat dihapus dari `GameOnlineOverlay.java`. Bakat asli game berfungsi lagi.
- Hub Online (Surat, Kode Hadiah, Daging) tetap terbuka lewat area LOGIN (kiri atas beranda) dan kotak avatar/nama panggilan.

## Daftar pemain di admin ("Belum ada super_admin aktif yang terhubung")
- Penyebab: `game-admin` mewajibkan baris `game_admin_users` yang terikat akun Supabase Auth, padahal pemain Google langsung tidak punya akun Auth dan bootstrap SQL harus diedit manual.
- Perbaikan: bila login admin utama (MAINTENANCE_ADMIN_NAME/PASSWORD) valid tetapi belum ada super_admin aktif, fungsi membuat otomatis akun layanan `admin-utama@kic-dtp.example.com` lalu menjadikannya super_admin. Bila MAINTENANCE_ADMIN_USER_ID diatur, akun itu yang dipakai.
- Nama pelaku di feed aktivitas memakai MAINTENANCE_ADMIN_NAME.

## Panel admin
- Sidebar bergaya ML: Maintenance, Pemain, Kode Hadiah, Surat, Aktivitas, Boss Gua, Event Shop. Di HP menjadi menu geser (tombol ☰).
- Halaman Pemain: tabel No, Nama, ID, Koin, DM, Goblin, Daging, Email, Status, Aksi, ringkasan total, pencarian, dan pengurutan.

## Urutan pasang
1. Deploy `kingdom-in-chaos-dtp-game-admin-function-v17_14_18.ts` (SQL tidak berubah).
2. Upload `kingdom-in-chaos-dtp-admin-v17_14_18.html` ke hosting admin.
3. Build APK ulang (perubahan Java).

## Belum diuji
- APK belum dibuild dan belum dites di perangkat; edge function belum dideploy dari sini. Admin diuji di browser headless dengan data tiruan.
