# v17.14.20 - Dialog Kode Hadiah asli kembali + hadiah admin masuk otomatis ke game

## Kode Hadiah (dialog "Masukkan kode promo" + Oke, seperti di screenshot)
- Dialog asli game dipakai lagi. Area sentuh buatan v17.14.19 untuk tombol Kode Hadiah tidak lagi menelan sentuhan; area itu kini diteruskan ke game.
- Penyebab kode tidak berfungsi: tombol "Oke" dialog asli memanggil `UIMallLayer::onInputPromoCode`, yang mengirim kode ke server promo bawaan game (sudah mati).
- Perbaikan: fungsi itu di-hook di `libkicgamebridge` (pola sama dengan hook barter). Kode (hanya A-Z, 0-9, "-") dikirim ke Java -> `GameOnlineOverlay.handlePromoCode` -> Edge Function `google-player` (`redeem_code`) -> hadiah masuk saldo native lewat jurnal anti-ganda (claim_id). Hasilnya muncul sebagai dialog "Kode berhasil diklaim!".
- Belum login Google -> muncul pemilih akun lebih dulu.
- Halaman `GameGiftCodeActivity` tetap ada di APK tetapi tidak dibuka lagi.

## Admin: hadiah benar-benar masuk (Kristal, Koin, Koin Goblin, Mata Event, Daging)
- Penyebab: sejak v17.14.19 layar Surat di game dihapus, sedangkan hadiah surat dulu baru masuk setelah pemain menekan Klaim di layar itu. Jadi Surat dari admin tidak pernah mengubah saldo.
- Perbaikan: aksi baru `pull_rewards` di `google-player`. Server mengklaim otomatis surat berhadiah milik pemain (RPC `game_google_claim_player_mail`, saldo server bertambah), lalu mengembalikan semua klaim surat + kode. APK memasukkannya ke saldo native lewat jurnal yang sama (anti-ganda per claim_id).
- APK menarik hadiah saat game dibuka dan kira-kira tiap 20 detik selama game terbuka. Bila function lama masih terpasang, APK memakai jalur lama sebagai cadangan.
- Mata Event di Surat sebelumnya diabaikan diam-diam oleh SQL; sekarang ikut dikreditkan.
- Panel admin: teks "pemain harus menekan Klaim" dihapus, ada isian Mata Event, status surat menjadi "Menunggu pemain online" / "Sudah masuk" / "Tanpa hadiah". `list_google_players` kini membawa `event_eyes`.

## Urutan pasang
1. Supabase SQL Editor: jalankan `kingdom-in-chaos-dtp-SQL-v17_14_20-hadiah-admin.sql` (atau `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17_14_20.sql` untuk instal baru). Tanpa tabel baru, aman diulang.
2. Deploy `kingdom-in-chaos-dtp-google-player-function-v17_14_20.ts` (function google-player) dan `kingdom-in-chaos-dtp-game-admin-function-v17_14_20.ts` (function game-admin).
3. Upload `kingdom-in-chaos-dtp-admin-v17_14_20.html` ke hosting admin.
4. Build APK ulang (perubahan Java + native C++).

## Belum diuji
- APK belum dibuild dan belum dites di perangkat; Java belum dikompilasi di sini (tidak ada Android SDK), hanya C++ yang lolos cek sintaks.
- Hook `onInputPromoCode` dipasang dari simbol libgame.so dan belum dicoba di HP. Perlu dicek: dialog menutup sendiri setelah "Oke" atau tidak (fungsi asli tidak dipanggil lagi).
- SQL/Edge Function belum dijalankan ke Supabase dari sini. Tes statis: 112 lulus.
- Tes lama v17.14.17/18 sekarang menunjuk ke file v17_14_20.
