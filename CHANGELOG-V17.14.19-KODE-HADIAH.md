# v17.14.19 - Hub Online dihapus, Kode Hadiah langsung dari game, hadiah diatur admin

## Dihapus
- Hub Online ("KINGDOM IN CHAOS DTP • ONLINE HUB"), layar Surat, dan layar Daging Misi (Java + manifest).
- Tombol LOGIN (kiri atas) sekarang membuka pemilih akun Google; bila sudah login muncul dialog kecil "Akun Google" dengan tombol Keluar Google.
- Setelah login/daftar pemain langsung kembali ke game (tidak lagi dibawa ke Hub).

## Kode Hadiah
- Penyebab bug: area sentuh tak terlihat kotak avatar (kiri bawah) menimpa tombol "Kode Hadiah" asli game di layar Toko, sehingga membuka Hub.
- Perbaikan: area baru khusus tombol Kode Hadiah (x 0.15-0.37 H, y 0.92-1.0 H) dicek lebih dulu dan membuka halaman klaim kode. Belum login -> pemilih akun Google lebih dulu.
- Hadiah kode dimasukkan ke saldo game (Koin, Kristal, Koin Goblin) lewat jurnal anti-ganda yang sama dengan Surat, memakai claim_id dari server. Dipulihkan otomatis bila aplikasi tertutup sebelum hadiah masuk.
- Mata Event dikreditkan ke saldo Mata Event akun (dipakai Event Shop).

## Admin
- Form kode hadiah: Mata Event, Kristal, Koin, Koin Goblin (Daging dihapus dari form). Tabel kode menampilkan hadiah dengan nama game.

## Urutan pasang
1. Jalankan `kingdom-in-chaos-dtp-SQL-v17_14_19-kode-hadiah.sql` di Supabase SQL Editor (atau GABUNGAN v17_14_19 bila instal baru).
2. Deploy `kingdom-in-chaos-dtp-google-player-function-v17_14_19.ts` (function google-player) dan `kingdom-in-chaos-dtp-game-admin-function-v17_14_19.ts` (function game-admin).
3. Upload `kingdom-in-chaos-dtp-admin-v17_14_19.html` ke hosting admin.
4. Build APK ulang (perubahan Java + manifest).

## Belum diuji
- APK belum dibuild dan belum dites di perangkat. Koordinat area tombol Kode Hadiah dihitung dari screenshot (layar 2340x1080) dan perlu dicek di HP.
- SQL/edge function belum dijalankan ke Supabase dari sini. Test statis: 107 lulus.
- Surat dari admin tidak lagi punya layar klaim di sisi pemain (layar Surat dihapus sesuai permintaan).
