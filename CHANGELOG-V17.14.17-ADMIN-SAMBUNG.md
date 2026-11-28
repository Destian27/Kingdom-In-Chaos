# v17.14.17 - ADMIN SAMBUNG (perintah & aktivitas admin tersambung 100% ke game)

## Akar masalah
Sejak login Google langsung (v17.13) pemain **tidak punya sesi Supabase Auth**. Tetapi jalur game untuk
**Boss Gua** dan **Event Shop** masih memakai `SupabaseGameBackend.hasSession()`:
- Event Shop: tanpa sesi, cache diisi `{}` (kosong) -> katalog dari admin tidak pernah tampil.
- Boss Gua: tanpa sesi, tidak diambil sama sekali -> perintah "Panggil Boss Sekarang" / jadwal tidak sampai.
- RPC `get_active_event_store` memakai `auth.uid()` dan dicabut dari `anon`, jadi tidak bisa dipanggil tanpa sesi.

## Perbaikan
- SQL: semua digabung dalam SATU file `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17_14_17.sql` (Bagian 3 = perubahan baru): fungsi `game_google_active_event_store(p_player_uuid)`
  (logika jadwal/katalog disalin persis dari fungsi lama, hanya sumber identitas & saldo Event Eyes yang diganti) + kolom
  `event_eyes` di `game_google_player_economy`. Hanya `service_role` yang boleh menjalankannya.
- Edge Function `google-player` v17.14.17: aksi baca-saja `get_cave_boss` dan `get_event_store` (token Google diverifikasi
  seperti aksi lain). Aksi ini tidak menulis `last_seen`/broadcast, jadi polling tidak membanjiri dashboard admin.
- Java: `GooglePlayerBackend.getCaveBoss()/getEventStore()`; `DtpApp` (poll Boss & Event Shop) dan `GameEventStoreActivity`
  memakai jalur Google bila tidak ada sesi Supabase. Dibatasi 1 request / 10 detik per jenis.
- Edge Function `game-admin` v17.14.17: perintah Boss/Event Shop dicatat dengan **alasan + ringkasan**
  (sebelumnya hanya `completed: true`), semua perintah (termasuk kode hadiah) memicu broadcast dashboard, dan riwayat
  **maintenance** (dari `app_maintenance_log`) ikut tampil di feed aktivitas.
- `admin.html`: label aktivitas berbahasa Indonesia, detail terbaca, filter pelaku + pencarian, feed otomatis segar
  setelah setiap perintah (Surat, kode hadiah, Boss, Event Shop, maintenance). Teks status yang menyesatkan diperbaiki.

## Urutan pasang
1. SQL Editor Supabase: jalankan HANYA `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17_14_17.sql` (sudah mencakup v17.14.8 + Daftar kata sandi + Admin Sambung).
2. Deploy `google-player` (`kingdom-in-chaos-dtp-google-player-function-v17_14_17.ts`) dan `game-admin`
   (`kingdom-in-chaos-dtp-game-admin-function-v17_14_17.ts`). `maintenance-admin` tidak berubah.
3. Upload `kingdom-in-chaos-dtp-admin-v17_14_17.html` ke hosting admin.
4. Build APK ulang dari paket ini (perubahan Java ikut).

## Yang belum / batas
- APK belum dibuild dan belum diuji di perangkat; edge function belum dideploy dari sini. Perubahan Java hanya diperiksa
  secara struktur teks.
- Saldo **Event Eyes** pemain Google dimulai 0 dan belum ada cara admin mengisinya (hadiah Surat/kode hanya mendukung
  coins, crystals, goblin_coins, meat). Perlu keputusan: tambah `event_eyes` ke hadiah Surat?
- Notifikasi instan "Surat baru" ke game belum ada: server sudah mengirim broadcast `mail_received`, tetapi game
  belum mendengarkannya. Surat muncul saat kotak surat dibuka.
- Aktivitas pemain yang tercatat tetap hanya: login, daftar, daging, kode, klaim Surat, perubahan saldo.
