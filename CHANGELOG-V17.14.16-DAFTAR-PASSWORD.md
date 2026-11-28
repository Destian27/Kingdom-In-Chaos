# v17.14.16 — Daftar dengan Nama Pengguna + Kata Sandi
- Setelah Google terverifikasi dan akun belum terdaftar, game membuka layar Daftar (gaya perkamen) berisi
  Nama Pengguna, Kata Sandi (4-16 karakter) dan Verifikasi Kata Sandi. Akun yang sudah terdaftar langsung ke Hub Online.
- google-player: complete_profile memvalidasi kata sandi, memeriksa nama pengguna unik, lalu menyimpan HASH PBKDF2-SHA256 + salt
  di tabel baru game_google_player_credentials (service_role saja). Kata sandi tidak pernah disimpan polos atau dikirim balik.
- SQL baru: kingdom-in-chaos-dtp-SQL-v17_14_16-daftar-password.sql (jalankan sebelum deploy function).
- Pesan error asli server kini ditampilkan (mis. "[HTTP 401] Invalid JWT") menggantikan "Permintaan server pemain gagal." saja.
- supabase/config.toml: verify_jwt = false untuk google-player (function memverifikasi token Google sendiri).
- Nama "DESTIAN HOSTING" di layar persetujuan Google bukan dari kode: ubah App name di Google Cloud Console.
- Belum dibuild/diuji di perangkat.
