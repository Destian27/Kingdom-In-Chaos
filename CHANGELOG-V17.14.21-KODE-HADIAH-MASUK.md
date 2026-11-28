# v17.14.21 - Kode Hadiah: dialog tidak lagi bilang "berhasil" sebelum saldo game benar-benar bertambah

## Yang ditemukan (dari membaca seluruh alur kode -> server -> saldo)
1. Dialog sukses lama (`showPromoResult`) muncul walau server TIDAK mengembalikan data hadiah (`claim`),
   mis. SQL di Supabase masih versi lama. Hasilnya "berhasil" tetapi tidak ada yang masuk ke saldo game.
2. Dialog sukses juga muncul sebelum hadiah diterapkan ke libgame.so, jadi kegagalan di tahap native tidak terlihat.
3. Pencarian GLSurfaceView hanya lewat refleksi `mGLSurfaceView`; bila gagal, hadiah menunggu terus tanpa kabar.
4. Hook `UIMallLayer::onInputPromoCode(const char*)` sudah dicocokkan dengan disassembly libgame.so: tanda tangan benar.

## Perbaikan
- Edge Function `google-player`: `redeem_code` SELALU mengembalikan `claim{claim_id, code, rewards}`;
  bila RPC lama tidak mengembalikannya, klaim yang baru dibuat dibaca dari tabel.
- APK: hadiah dimasukkan ke jurnal lalu diterapkan ke game; dialog sukses baru muncul setelah jurnal berstatus
  "applied". Bila belum masuk dalam 15 detik, dialog jujur menjelaskan hadiah tersimpan, dicoba lagi otomatis,
  beserta kode status native (untuk diagnosis).
- Cadangan pencarian GLSurfaceView lewat pohon view.
- Kode hanya Mata Event: dialog menyebut hadiah dipakai di Event Shop (tidak ada saldo native yang berubah).

## Urutan pasang
1. Pastikan SQL `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17_14_20.sql` sudah dijalankan penuh di Supabase.
2. Deploy `kingdom-in-chaos-dtp-google-player-function-v17_14_21.ts` (function google-player).
3. Ganti dua file Java di `dtp/src/com/destian/dtp/`, lalu build APK ulang.

## Belum diuji
- Belum dibuild dan belum dites di HP. Java tidak dikompilasi di sini (tidak ada javac/Android SDK); hanya
  keseimbangan kurung dan tes statis lama yang dicek. Kode di Supabase juga belum dijalankan dari sini.

## Tambahan v17.14.21: sinkron saldo 2 detik + avatar setelah login
- `DtpApp.java`: saldo native game (Koin, Kristal, Koin Goblin, Daging) dilaporkan ke admin tiap 2 detik
  (sebelumnya 10 detik); penarikan hadiah admin tiap 10 detik.
- `google-player`: `sync_native_wallet` hanya membangunkan dashboard admin bila saldo berubah atau tiap 10 detik
  (denyut), supaya broadcast tidak membanjir. Admin tetap menerima perubahan lewat realtime.
- Bug avatar: setelah login Google, kotak avatar/nama panggilan memunculkan dialog "Akun Google" yang menutupi
  pilihan Avatar asli game. Sekarang sentuhan di kotak itu diteruskan ke game saat sudah login. Dialog Akun Google
  tetap ada di tombol LOGIN (kiri atas).
- Belum diuji di HP/Supabase; Java belum dikompilasi di sini.

## Tambahan v17.14.21 (2): tidak lagi terjebak di halaman login
- Penyebab: area sentuh LOGIN/avatar menempel di semua layar game; setelah login ia tetap menelan sentuhan
  sehingga dialog "Akun Google" muncul alih-alih tombol game yang diklik di halaman berikutnya.
- Perbaikan: setelah login Google, semua sentuhan diteruskan ke game. Area itu hanya aktif sebelum login.
- Konsekuensi: dialog "Keluar Google" tidak lagi bisa dibuka dari layar game setelah login.
