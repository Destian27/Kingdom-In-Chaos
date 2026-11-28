# CHANGELOG — v1.0.7 Login Nama Pengguna + Kata Sandi (Google dihapus total)

## Game (APK) — versionName 1.0.7, versionCode 107
- Layar login baru `GameAuthActivity` (gaya perkamen seperti layar Daftar): mode **Masuk** (Nama Pengguna + Kata Sandi)
  dan mode **Daftar** (+ Verifikasi Kata Sandi, 4–16 karakter). Tombol bawah beralih Masuk <-> Daftar.
- Dihapus total: login Google (`GoogleAccountPickerActivity`, `GameProfileSetupActivity`, token Google/GoogleAuthUtil/AccountManager,
  OAuth+PKCE Supabase lama, izin `GET_ACCOUNTS` & `USE_CREDENTIALS`).
- `GooglePlayerBackend` -> `PlayerBackend`. Perangkat hanya menyimpan token sesi (bukan kata sandi). Token ditolak server (401) -> otomatis keluar.
- Sesi Google lama di perangkat dibersihkan saat aplikasi dibuka; pemain masuk lagi dengan nama pengguna + kata sandi.
- Tombol LOGIN / avatar di game membuka layar Masuk/Daftar; setelah masuk, dialog akun punya tombol Keluar.

## Server (WAJIB dipasang, urutan ini)
1. Supabase SQL Editor: jalankan `kingdom-in-chaos-dtp-SQL-v1_0_7-login-password.sql` (aman diulang; menambah kolom pembatas percobaan salah).
2. Edge Function `google-player` (nama tetap agar URL di APK sama): ganti seluruh kodenya dengan
   `kingdom-in-chaos-dtp-player-function-v1_0_7.ts` lalu Deploy. **Verify JWT harus MATI** (sudah di `supabase/config.toml`).
3. (Opsional) secret function `PLAYER_SESSION_SECRET` = string acak panjang untuk menandatangani token; bila kosong dipakai turunan dari service role key.

## Server — cara kerja
- `register` / `login` tanpa sesi -> server mengembalikan `{ token, profile, economy }`. Token = HMAC-SHA256, berlaku 180 hari.
- Semua aksi lain (`get_state`, `redeem_code`, `pull_rewards`, `sync_native_wallet`, Boss Gua, Event Shop, dst.) memakai `Authorization: Bearer <token>`.
- Kata sandi: hash PBKDF2-SHA256 + salt acak (tabel `game_google_player_credentials`, hanya service_role). 5x salah -> terkunci 5 menit.
- Akun baru memakai kunci internal `google_sub = local:<uuid>` dan email sintetis agar tabel, RPC, dan dashboard admin lama tetap bekerja tanpa perubahan.
- Akun lama yang dulu daftar lewat Google DAN sudah punya kata sandi (sejak v17.14.16) bisa masuk dengan nama pengguna + kata sandi itu.
  Akun lama tanpa kata sandi tidak bisa masuk; pemain membuat akun baru (nama pengguna harus unik).
- Label aktivitas admin `google_login` kini tampil "Pemain masuk (login)".

## Batasan
- Belum dibuild/diuji di perangkat dan server (tidak ada SDK/Deno di sini). Kode Java lolos pemeriksaan sintaks `javac`, TypeScript lolos parse Node,
  dan tes struktur (`tests/`) lolos.
