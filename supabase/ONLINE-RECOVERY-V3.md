# Kingdom in Chaos DTP — Online Recovery v3

Tanggal: 26 November 2026

## Isi pembaruan
- `supabase/online-backend-complete.sql`: skema online sebelumnya ditambah recovery migration v3.
- `supabase/migrations/202611260002_online_recovery_v3.sql`: migrasi tambahan untuk proyek yang sudah menjalankan backend v2.
- `supabase/functions/game-online/index.ts`: review gateway TypeScript v2, dengan pemeriksaan request size, validasi UUID, allowlist CORS opsional, dan error publik yang tidak membeberkan detail SQL.
- Java adapter menambahkan pembacaan status match PvP melalui RPC `get_my_pvp_match_state`.
- Layar Online Hub menampilkan kolom Match UUID dan tombol pemeriksaan status match.

## Cara menerapkan SQL

**Proyek baru:** jalankan seluruh `supabase/online-backend-complete.sql` sekali di Supabase Dashboard → SQL Editor.

**Proyek yang sudah menjalankan SQL backend v2:** jalankan hanya `supabase/migrations/202611260002_online_recovery_v3.sql`. Jangan jalankan urutannya terbalik.

Setelah migrasi, verifikasi:
```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('game_player_save_history', 'game_online_review_audit');

select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('get_my_pvp_match_state',
                       'admin_review_world_boss_claim',
                       'admin_review_pvp_result');
```

## Deploy function server

Function menggunakan `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, dan secret kuat `KIC_SCORE_REVIEW_KEY`. Secret review harus disetel di konfigurasi secrets Edge Function dan tidak boleh dimasukkan ke APK atau repository. Buat key acak kuat di perangkat tepercaya, misalnya dengan `openssl rand -hex 32`.

Contoh deployment dari lingkungan yang memiliki Supabase CLI dan terhubung ke proyek yang benar:
```bash
supabase secrets set KIC_SCORE_REVIEW_KEY=<KEY_ACAK_KUAT>
supabase functions deploy game-online --no-verify-jwt
```

`--no-verify-jwt` dipakai karena gateway ini memeriksa header `x-kic-review-key` sendiri. Jangan memanggil endpoint privileged ini dari APK, jangan memaketkan key tersebut di game, dan batasi penggunaan hanya ke administrator tepercaya. Untuk admin panel browser, isi `KIC_REVIEW_ALLOWED_ORIGINS` dengan origin persis yang diizinkan; tanpa konfigurasi itu request native tanpa header Origin tetap diperbolehkan, tetapi origin browser ditolak.

Contoh request review (jalankan dari lingkungan admin tepercaya):
```json
{
  "action": "approve_world_boss",
  "claim_id": "UUID-CLAIM",
  "confirmed_by_human": true,
  "note": "Replay diperiksa oleh reviewer"
}
```
Untuk `approve_pvp`, kirim `match_id`, `winner_user_id` (UUID peserta atau `null` untuk seri), objek `battle_summary`, `confirmed_by_human: true`, serta catatan review minimal 8 karakter. Endpoint juga mendukung `list_pending_world_boss` dan `list_open_pvp`.

## Batas yang masih harus diselesaikan sebelum menyebut 100% pulih
1. PvP queue membuat/mencari record pertandingan dan status, tetapi **tidak menjalankan simulasi pertarungan native**. Hasil hanya boleh disahkan setelah battle/replay nyata diperiksa oleh trusted verifier.
2. World Boss menyimpan klaim skor dan menunggu review. SQL tidak dapat membuktikan keabsahan replay tanpa format replay/engine game yang sesuai.
3. Riwayat save kini disimpan sebelum perubahan, tetapi native game belum mengirim dan memulihkan save aslinya melalui adapter. JSON yang dikirim klien tetap tidak boleh menjadi sumber resmi mata uang, hadiah, atau ranking.
4. Pengiriman hadiah dan update mata uang resmi memerlukan pemetaan format save/game-state asli serta fungsi backend tepercaya yang belum tersedia dalam source.
5. File TypeScript dan SQL diperbarui, tetapi migrasi belum dijalankan pada proyek Supabase pengguna dan APK final belum dibuat/diuji. Jangan menandai layanan online pulih sebelum tes akun kedua, dua klien PvP, save round-trip, dan klaim/review World Boss berhasil di perangkat nyata.

Jangan pernah memasukkan `service_role` atau `KIC_SCORE_REVIEW_KEY` ke dalam APK.
