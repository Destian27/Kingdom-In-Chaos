# Kingdom in Chaos DTP — v17.2 Event Shop Realtime

## Polling Event Shop
- Supabase Realtime WebSocket tetap menjadi jalur push utama untuk perubahan katalog dan konfigurasi.
- Cadangan Event Shop di Android melakukan refresh setiap **1 detik** pada gameplay maupun layar Event Shop. Ini berlaku juga saat WebSocket putus atau peristiwa perubahan jadwal perlu dideteksi.
- Karena polling 1 detik menghasilkan hingga sekitar satu permintaan status per detik untuk tiap sesi game aktif, gunakan hanya pada build dan proyek Supabase yang memang menginginkan interval ini. `loadBusy` / refresh coalescing mencegah permintaan paralel menumpuk.
- Interval maintenance (2 detik), Cave Boss (15 detik), timeout baca socket, dan jeda reconnect WebSocket tetap terpisah dan tidak diubah.

## SQL gabungan
Untuk database baru, jalankan **satu file ini saja** di Supabase SQL Editor sebagai project owner:

- `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.3-ALL-IN-ONE.sql` (salinan identik juga tersedia di `supabase/`).

File tersebut menyatukan fondasi online v15, strict maintenance gate, admin economy, Cave Boss v16, native economy revision bridge, serta Event Shop dan Event Eyes v17. Jangan menjalankan seluruh file di `supabase/migrations/` sekaligus setelah All-in-One.

Untuk project yang sudah sampai v16, jalankan hanya migrasi tambahan Event Shop `supabase/migrations/202611260006_event_store_v17.sql` setelah prasyarat v15/v16 sudah diterapkan. Jangan jalankan All-in-One pada database yang sudah terisi tanpa rencana migrasi karena file itu ditujukan untuk instalasi baru.

## Deploy
1. Deploy `supabase/functions/game-admin/index.ts` sebagai Edge Function `game-admin`. Simpan service-role key hanya pada secrets server.
2. Host `admin.html` dan daftarkan operator pada `game_admin_users`.
3. Build APK dari source menggunakan workflow `.github/workflows/build-apk.yml` atau `python3 build_dtp.py` dalam lingkungan yang memiliki Android SDK/NDK.
4. Verifikasi Realtime channel dan polling satu detik pada perangkat setelah migrasi/deploy. ZIP berisi source; bukan APK siap pasang.

## Batas integrasi
Mata Event diterapkan lewat native key FestivalActivityScorePoint. Event Shop masih berupa katalog/layar baca; transaksi pembelian dan pengiriman gear ke inventory native belum diaktifkan.


## v17.3 TypeScript Realtime

The `game-admin` Edge Function sends Broadcast invalidations after Event Shop, economy, profile, and cloud-save admin writes. Android subscribes to the matching topics and reloads authenticated RPC snapshots. Postgres Changes remains enabled, and polling remains a 1-second fallback. Apply migration `202611260007_player_event_realtime_v17_3.sql` to an existing v17.2 database and redeploy `supabase/functions/game-admin/index.ts`.


## v17.3 TypeScript Realtime

The `game-admin` Edge Function sends Broadcast invalidations after Event Shop, economy, profile, cloud-save, and Cave Boss admin changes. Android subscribes to matching topics and reloads authenticated RPC snapshots. Postgres Changes remains enabled. Event Shop polling remains a 1-second fallback; Cave Boss refresh retains a 15-second fallback. Apply migration `202611260007_player_event_realtime_v17_3.sql` to an existing v17.2 database and redeploy `supabase/functions/game-admin/index.ts`.
