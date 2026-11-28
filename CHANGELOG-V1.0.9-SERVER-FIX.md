# v1.0.9 - Perbaikan "Google ID token tidak valid atau kedaluwarsa" saat Daftar

## Penyebab
APK v1.0.8 sudah memakai Nama Pengguna + Kata Sandi (tanpa Google). Pesan "Google ID token tidak valid..."
hanya bisa keluar dari Edge Function `google-player` VERSI LAMA (v17.14.x). Artinya function di Supabase
belum diganti dengan kode v1.0.9 (v1.0.7), sehingga server lama menganggap permintaan Daftar sebagai token Google.

## Yang diperbaiki
- Function baru `kingdom-in-chaos-dtp-player-function-v1_0_9.ts` (= v1.0.7 + aksi `ping` untuk cek server).
- SQL tunggal `kingdom-in-chaos-dtp-SQL-GABUNGAN-v1_0_9-FINAL.sql` (v17_14_20 + kolom pembatas login v1.0.7).
- APK: bila server masih versi lama, game kini menampilkan "Server belum diperbarui: ganti kode function google-player..."
  alih-alih pesan Google yang membingungkan. versionCode 109 / versionName 1.0.9.

## Urutan pasang (WAJIB berurutan)
1. Supabase > SQL Editor: jalankan penuh `kingdom-in-chaos-dtp-SQL-GABUNGAN-v1_0_9-FINAL.sql`.
2. Supabase > Edge Functions > `google-player` > ganti SELURUH kode dengan `kingdom-in-chaos-dtp-player-function-v1_0_9.ts` > Deploy.
   Pastikan "Verify JWT" MATI.
3. Cek server: kirim POST ke https://gunzwimrxspbmiducphg.supabase.co/functions/v1/google-player dengan body {"action":"ping"}
   (header apikey = anon key). Hasil benar: {"ok":true,"data":{"version":"1.0.9-password",...}}.
4. Build APK v1.0.9, pasang, lalu Daftar.

## Belum diuji
Tidak ada Deno/Android SDK di sini; server Supabase kamu tidak bisa diakses dari sini. TypeScript lolos parse Node,
tes struktur lolos, Java hanya dicek keseimbangan kurung.

## Tambahan SQL (BAGIAN 5 + perbaikan)
- Index nama pengguna unik kini aman: bila ada nama kembar di data lama, SQL tidak gagal total (hanya memberi NOTICE).
- `notify pgrst, 'reload schema'` di akhir agar kolom/tabel baru langsung terbaca Edge Function.
- Laporan cek otomatis di akhir (tabel, kolom, index, fungsi): semua baris harus "OK".
- Audit statis: semua tabel, kolom, dan RPC yang dipakai function player + admin ada di SQL; tidak ada konflik tipe kembalian fungsi;
  semua policy/trigger/publication aman diulang.
