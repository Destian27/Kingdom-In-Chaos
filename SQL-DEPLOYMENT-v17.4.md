# Kingdom in Chaos DTP — SQL Deployment v17.4

## Satu file kanonis

Gunakan **`kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.4-ALL-IN-ONE.sql`** untuk instalasi baru atau pembaruan penuh. Salinan di root proyek dan `supabase/` harus identik.

File ini menggabungkan fondasi online v15, maintenance strict, admin/economy, Cave Boss v16, Event Shop + Event Eyes v17, dan publikasi Realtime v17.3 (migration 007), termasuk `REPLICA IDENTITY FULL` untuk tabel player/event yang dipantau.

Jalankan seluruh file satu kali melalui Supabase Dashboard → SQL Editor sebagai project owner. File melakukan preflight dan berhenti dengan pesan jelas sebelum perubahan skema bila publication `supabase_realtime` belum tersedia atau tabel wajib tidak ditemukan.

## Proyek yang sudah ada

- Proyek yang sudah di v17.2 dapat menjalankan seluruh SQL gabungan v17.4 untuk menyelaraskan semua objek, atau menggunakan migration `202611260007_player_event_realtime_v17_3.sql` saja bila seluruh tabel v17.2/migration 006 telah ada.
- Jangan menjalankan migration 007 bersamaan dengan full SQL bundle; bagian Realtime yang sama sudah ada di dalam bundle.
- File migration `001`–`006` dipertahankan sebagai jalur upgrade historis. Jangan jalankan ulang seluruh migration historis pada database yang sudah menerapkan full SQL bundle.
- File SQL lama tetap berada di paket untuk referensi/kompatibilitas. Untuk instalasi baru, gunakan hanya file kanonis v17.4.

## Pemeriksaan dan batas validasi

Bundle sudah diperiksa secara statis: delimiter/quote/comment/parentheses seimbang, pasangan BEGIN/COMMIT seimbang, objek Realtime yang diwajibkan terdaftar, dan dua salinan SQL sama persis. Ini bukan pengganti eksekusi terhadap PostgreSQL/Supabase target. Hasil akhir tetap perlu diuji pada proyek Supabase yang sesungguhnya karena role, extension, objek yang telah ada, hak akses, dan riwayat migrasi dapat berbeda.

Jangan pernah memasukkan `service_role` key ke APK atau HTML admin. Simpan hanya pada environment secret Edge Function.
