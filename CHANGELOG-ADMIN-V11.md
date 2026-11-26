# Admin v11 — Data Pengguna dan Statistik

- Memperbarui `admin.html` yang awalnya hanya berisi maintenance agar memiliki halaman Manajemen Data Pemain.
- Menambahkan login Supabase Auth terpisah untuk data pemain; role aktif diverifikasi server-side lewat tabel admin privat.
- Menambahkan daftar pengguna berhalaman dan pencarian email/ID/username/nickname pada halaman saat ini.
- Menambahkan detail Auth yang aman, profil game, presence, ranking, ekonomi admin, riwayat save cloud, payload save cloud JSON, dan audit perubahan.
- Menambahkan pengeditan username/nickname/avatar/region.
- Menambahkan pengeditan coins, crystals, goblin coins, hero XP/level, player XP/level, energy, stamina, honor, arena tokens, skill points, dan extra_stats JSON.
- Menambahkan edit save cloud JSON dengan validasi ukuran/bentuk dan pencatatan audit.
- Menambahkan migration SQL private untuk admin/economy/audit dengan RLS dan tanpa akses langsung anon/authenticated.
- Menambahkan Edge Function `game-admin`, validasi access token Supabase Auth, pengecekan allowlist admin aktif, validasi input dan audit log.
- Tidak mengekspos password, hash password, access token, refresh token atau service-role key di panel.
- Perlu pemasangan migration + deployment Edge Function dan whitelist email admin sebelum digunakan.
- Nilai ekonomi admin disimpan di backend table terpisah; belum otomatis mengubah save lokal/ekonomi dalam mesin native game sampai format save native terintegrasi.
