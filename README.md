## v17.14.6 — Wallet crash fix (27 November 2026)

Game keluar sendiri tepat setelah layar maintenance lolos (tekan **Cek Lagi** atau buka dengan data seluler) karena `SIGSEGV` di `DHValue::getValue()`. Penyebab: pembacaan saldo native di thread UI saat game baru dibuka, sebelum data `LevelManager` dimuat. Lihat `CHANGELOG-V17.14.6-WALLET-CRASHFIX.md`.

## v17.14.3 — Google OAuth Client ID (27 November 2026)

- Web OAuth Client ID diberikan dan dikonfigurasi di `supabase/functions/google-player/index.ts` sebagai `GOOGLE_WEB_OAUTH_CLIENT_ID`.
- Backend dapat memvalidasi Google ID token dengan audience Web Client ID; access token Android tetap memakai verifikasi userinfo dan, bila diisi, `GOOGLE_ANDROID_OAUTH_CLIENT_ID`.
- Client Secret tidak dimasukkan ke source, APK, atau repo. Native access-token flow tidak memerlukannya. Secret yang sudah dibagikan perlu dirotasi.
- Lihat `GOOGLE-AUTH-SETUP-v17.14.3.md`. Perubahan TS ini tidak membangun ulang APK.

# Kingdom In Chaos DTP

## Current source revision — v17.14.2

This source revision combines direct Google player sign-in, the second-stage nickname/player-ID setup, the in-game **Surat** mailbox, one-time server-side mail claims, native wallet application, a 5-minute native food regeneration setting, the read-only Google player dashboard, and the reported `LifeMax()` crash guard.

Admin gifts are sent to a player's in-game **Surat** inbox (the email address is only used to find the Google player). Admin cannot directly edit a player's profile, wallet, or cloud save in this dashboard; players' Google profile picture/identity and observed native wallet values update the dashboard through Realtime broadcasts with periodic polling fallback. This requires a network connection and is near-realtime, not guaranteed during offline periods. The native character avatar remains owned by the original game's local character data; the current bridge does not claim that every in-game avatar selection has been synchronized.

The native crash report supplied for v17.11 points to `UIAchieveLayer::onAward() -> LifeMax()` on ARMv7. `tools/patch_lifemax_crash.py` applies an exact-byte-checked guard to both `armeabi` and `armeabi-v7a`; the patched function returns the configured life cap of 24. The patch has been checked by disassembly, but still requires device testing in a rebuilt APK.

Source tests: **95 passed, 2 skipped** (APK-only checks). An APK has **not** been built or device-tested in this environment. Google OAuth still needs the deployment's own OAuth client/SHA-1 configuration, and the SQL migrations plus Edge Functions must be deployed to the project's Supabase database/function host.

The expected build output is `KingdomInChaosDTP-v17.14.2-google-mail-crashfix.apk`. See `CHANGELOG-V17.14.2-ADMIN-READONLY.md` and `CHANGELOG-V17.14-MAIL-CRASHFIX.md`.

---

 (v17.12) — Barter Economy (Android 7+)

Compatibility port and offline patch for **Kingdom in Chaos** (`com.droidhang.zhanshen` / 战神传说), originally released by Droidhang in 2013. This DTP build keeps its maintenance-screen / Supabase integration and replaces real-money offers with native Koin/DM barter transactions.

The game originally crashes immediately on Android 6.0 and newer versions due to deprecated APIs, `DT_TEXTREL` dynamic relocations, dead telemetry services, and uninitialized graphics contexts. This repository contains the decompiled source, binary patches for `libgame.so`, and an automated build script to produce a working APK for modern Android devices.


## v17.9 — Automatic full crash report

- A crash/session marker is retained across ordinary Activity pauses so a process death while the game is backgrounded can still be diagnosed. It is cleared only for explicit normal game finishing or the intentional maintenance kick.
- A previous-session marker is rotated at startup and preserved until the report is written successfully.
- The app now captures uncaught Java exceptions before chaining to Android's original crash handler.
- On relaunch, the full report is automatically shown on the maintenance/launcher screen; the small warning icon in the game can reopen it.
- The report includes device/build/app version, session breadcrumbs, Java stack trace when available, Android 11+ process-exit reasons and available trace/tombstone text, plus relevant logcat entries. Secrets/tokens are redacted.
- Reports remain in private app storage until the player deletes them. Android may restrict some logcat/tombstone data, so completeness depends on OS access.
- Android package version is `17.9` (versionCode `7`).

---

## v17.12 — Barter Economy

- Cash purchase entry points are disabled; the ARMv7 native hook deducts Koin/DM before the original reward callback grants VIP, hero, equipment, and gift items.
- A BARTER menu converts Koin and DM in both directions and lists barter prices for store packages. The native wallet is read from the game runtime.
- The cumulative-DM meter counts crystals actually added to the wallet; spending DM does not reduce the lifetime counter.
- Legacy cash-payment recording and paid-purchase analytics are disabled.
- See [CHANGELOG-V17.12-BARTER-ECONOMY.md](CHANGELOG-V17.12-BARTER-ECONOMY.md) for price assumptions and limitations.

## Summary of Applied Fixes (Crystal Shop + DTP)

The patches below resolve crash causes, obsolete APIs, and offline gameplay issues:

| Fix | Component | Description |
|---|---|---|
| **Fix 1** | Target SDK & Manifest | Updated `targetSdkVersion` to 28, keeps the DTP maintenance screen as the exported launcher and `GameActivity` non-exported, adds `org.apache.http.legacy`, enables `usesCleartextTraffic`, removes deprecated `READ_PHONE_STATE`, and disables dead third-party ad services (Vungle, SponsorPay, Fyber). |
| **Fix 2** | Native ABIs & Cleanup | Removed `libbspatch.so` and `libgetuiext.so`, which caused fatal linker crashes on Android 6.0+ due to `DT_TEXTREL`. Removed `libNativeCrash.so` (Breakpad crash handler). Added `armeabi-v7a` alongside `armeabi`. |
| **Fix 3** | Java FloatMath Fix | Replaced deprecated `Landroid/util/FloatMath;->ceil(F)F` calls in `Cocos2dxBitmap.smali` with `java.lang.Math.ceil`, preventing `NoSuchMethodError` crashes on Android 6+. |
| **Fix 4** | GL Lifecycle Guard | Added `sNativeInitDone:Z` guard to `Cocos2dxRenderer.smali` to prevent `handleOnPause()`, `handleOnResume()`, `onDrawFrame()`, and touch/key handlers from calling native renderer methods before GL surface initialization completes. |
| **Fix 5** | Signature & Telemetry Bypass | Spoofed `AndroidUtil.getSignatureMd5()` in Smali with the original APK signature MD5 (`e3642530816912682978ad8c491ccbe7`). Replaced native `verify` (`0x0025DDD4`) with `bx lr` to bypass `exit(0)`, neutralized `DHHttpHelper::login` (`0x003DEB18`), and neutralized Umeng/MobClickCpp telemetry (`0x0062E40C` - `0x0062F1D0`) in `libgame.so`. |
| **Fix 6** | Unlimited Stamina | Patched `BalanceLifeStatus` (`0x003053A0`) and `DecreaseLife` (`0x003055FC`) in `libgame.so` so stamina stays at 5/5 and stages consume 0 energy. Prevents UI drumstick icon overflow. |
| **Fix 7** | Original Hero Purchase Flow | Removed the previous patches that forced every hero unlocked and made `payUnlockHero` always succeed. Hero locks and the original Crystals deduction / purchase checks are retained. |
| **Fix 8** | Window Focus Race Condition | Guarded `BEUtil.onWindowFocusChanged` and `BEUtil$8.run()` with `sNativeInitDone`, and stubbed native `BEUtil::nOnWindowFocusChanged` (`0x003DA62C`) with `bx lr` to prevent dereferencing uninitialized singletons (`SIGSEGV`). |
| **Fix 9** | Legacy SDK Disablement | Disabled obsolete SDK initializations in `GameActivity.smali` (`MobclickAgent`, `TapjoyConnect`, `DHGames`, `CrossPromotionUtil`, `DHGooglePaymentManager`, `AdMgr`, `SponsorPay`). |
| **Fix 10** | Testin Crash Reporter | Disabled Testin Agent v2.0.7 (`TestinAgent.smali` and `com/testin/agent/e/b.smali`) and stubbed native `TestinAgentHelper` functions (`0x00441CC0`, `0x00441824`, `0x00441F04`, `0x00441CE0`, `0x00441DB0`, `0x00441E34`, `0x00441EE8`, `0x00441F20`) to prevent `Process.killProcess()` calls. |
| **Fix 11** | In-App Billing Bypass | Disabled Google In-App Billing v3 service initialization in `DHGooglePaymentManager.smali` and added null checks to `handleActivityResult` to prevent startup crashes. |
| **Fix 12** | Storage Deletion Guard | Added null check to `IOUtil.delete(File)` when `File.listFiles()` returns `null` on restricted or missing storage paths. |
| **Fix 13** | Device Identifier Stubs | Stubbed `AndroidUtil.getWIFI`, `getIMEI`, and `getIMSI` to return dummy values, preventing `NullPointerException` and Android 10+ `SecurityException` crashes. |
| **Fix 14** | Preload Layer and Helper Initialization | Moved `Cocos2dxHelper.init` before GLSurfaceView initialization in `Cocos2dxActivity.smali` so APK asset paths configure before rendering starts. Guarded `PreloadLayer::init` (`0x00271546` and `0x0027173E`) against null sprite pointers. |
| **Fix 15** | Asset Decryption and Texture Guard | Initialized `DHEncrypt::_key` with the 32-character XXTEA key (`e3642530816912682978ad8c491ccbe7`) at startup (`0x0047B4FC`), bypassed broken dynamic key generation in `AndroidUtil::init` (`0x003D8F66`), and routed `CCTexture2D::hasPremultipliedAlpha` (`0x00484472` -> `0x002E17E0`) through a null guard to prevent crashes when loading decrypted textures. |
| **Fix 16** | Crystal Shop Conversion | Converts the six cash-priced hero unlocks and configured gear/hero/week/luck-gift prices from payment type `5` to Crystals type `1` in the packed `hero.xml` and `price.xml` configs. Removes the unlimited-currency injection so Crystals purchases can check and deduct the real balance. |
| **Fix 17** | Top Up UI Disabled | NOPs the native money-button insertion at `0x0035769E` and returns from `UIFloatingWindow::onBank` at `0x00358958`, hiding the Top Up button and blocking its navigation while leaving the normal Crystals shop enabled. |
| **Fix 18** | Top Up button no longer dangles (v17.11) | Fix 17 removed the `addChild` of the money button, so the autoreleased button was freed while `UIFloatingWindow+0x12C` still pointed at it, causing SIGSEGV in `UIFloatingWindow::setAllEnabled` when the tutorial begins. The removed call (`0x35769E`) is now preceded by an inline `CCObject::retain` of the button (`0x357698`: `ldr r3,[r1,#12]; adds r3,#1; str r3,[r1,#12]`), so the button stays alive, unattached and invisible. |

---

## Repository Structure

```
├── build_dtp.py                     # Build DTP APK from the checked-in modified source
├── kingdom-in-chaos-decompiled/     # Decompiled game source, packed configs, patched native libraries
│   ├── assets/public/config/        # Crystal-priced hero and gift configuration
│   ├── lib/armeabi/                 # Patched libgame.so
│   └── lib/armeabi-v7a/             # Matching patched ARMv7a libgame.so
├── dtp/src/                         # Maintenance screen, Supabase REST/realtime client
├── supabase/                        # Maintenance SQL setup and toggles
├── .github/workflows/build-apk.yml  # GitHub Actions APK build workflow
└── tests/                           # Source compatibility and monetization checks
```

## Testing and Verification

Run the source compatibility and barter economy checks with pytest. The current source suite reports 79 passed and 2 APK-only checks skipped until a signed APK has been built:

```powershell
pytest
```

---

## Building the APK

Build the DTP edition from the checked-in source (including the native barter economy changes):

```bash
python3 build_dtp.py
```

This creates `KingdomInChaosDTP-v17.14.2-google-mail-crashfix.apk`. A local build requires JDK 17+, Android SDK build-tools, an Android platform `android.jar`, and `tools/apktool.jar`. The GitHub Actions workflow downloads apktool automatically. Do **not** use the legacy `build_apk.py` script for this DTP source tree.


---

## Crystal Shop Conversion Notes

- Six hero unlocks that originally used payment type `5` now use Crystals (`type="1"`) with configured prices of **140, 350, 1,400, 490, 490, and 700 Crystals** for hero keys `3`, `6`, `8`, `12`, `14`, and `15`.
- Configured gear / hero / weekly / lucky-gift cash offers were changed to Crystals. The amounts use an estimate of about **70 Crystals per USD**, anchored on the original 700-Crystal / $9.99 bundle. The game does not define an official exchange rate for these specific offers, so these converted prices are estimates, not official prices.
- The Top Up entry point is hidden and bank navigation is disabled; Google Play billing remains disabled by the compatibility patch.
- Gold, Crystals, and Goblin Coins are no longer forced to 999,999 by the removed currency injection. Ordinary purchase checks can use and deduct the player's real Crystals balance.
- The DTP maintenance / Supabase features from this project are preserved. The checked-in `build_dtp.py` is the build entry point; the legacy `build_apk.py` is for the previous non-DTP build and should not be used for this project.

## Kingdom In Chaos DTP

| Item | Nilai |
|---|---|
| Nama app | Kingdom In Chaos DTP |
| Package | `com.destian.kingdominchaosdtp` |
| minSdk / targetSdk | 24 (Android 7.0+) / 28 |
| Backend | Supabase REST, tabel `app_maintenance` |

**Maintenance.** Launcher sekarang `com.destian.dtp.MaintenanceActivity` (source di `dtp/src`). Saat dibuka, app membaca `app_maintenance` dari Supabase. Kalau `is_active = true` dan `end_at` belum lewat, game tidak bisa dimasuki dan yang tampil hitung mundur hari, jam, menit, detik. `GameActivity` tidak lagi exported, jadi tidak bisa dibuka langsung. Hitung mundur memakai jam server (header `Date`), jadi mengubah jam HP tidak berpengaruh. Layar mengecek ulang tiap 15 detik dan otomatis masuk game begitu maintenance selesai atau dimatikan.

Setup database: jalankan `supabase/maintenance.sql` sekali di SQL Editor. Nyalakan atau matikan maintenance lewat contoh di `supabase/maintenance_toggle.sql`.

**Realtime (v2).** `DtpApp` (Application) memantau status maintenance saat `GameActivity` tampil: koneksi realtime Supabase lewat `RealtimeClient` ditambah polling 2 detik sebagai cadangan. Begitu maintenance aktif, pemain langsung dikeluarkan lewat `KickActivity` (proses `:kick`) ke layar maintenance. Jalankan ulang `supabase/maintenance_admin.sql` sekali di SQL Editor (aman diulang) untuk tabel log dan publikasi realtime.

Opsi di `MaintenanceActivity.java`: `BLOCK_WHEN_OFFLINE` (default `false`, artinya kalau tidak ada internet game tetap bisa dibuka).

**Build.** Push ke GitHub lalu jalankan workflow `Build Kingdom In Chaos DTP APK`, hasilnya artifact `KingdomInChaosDTP-v17.9.apk`. Build lokal: `python3 build_dtp.py` (butuh JDK 17+, Android SDK, dan `tools/apktool.jar`). Jangan jalankan `build_apk.py` lama, itu untuk port sebelumnya.

Agar update APK bisa menimpa versi lama, simpan keystore sebagai secret `KEYSTORE_BASE64` (plus `KEYSTORE_PASS` dan `KEYSTORE_ALIAS`). Tanpa secret itu, build memakai keystore tetap `keystore/dtp-fixed.keystore` (alias `kingdomchaosdtp`, password `android123`) sehingga tanda tangan APK selalu sama. Jangan dihapus atau diganti, kalau tidak update akan gagal "Aplikasi tidak terinstal".

## Supabase online backend (v2 integration adapter)

Additional files now included:

- `supabase/online-backend-complete.sql`: one combined setup script (foundation + v2). Run this once in the Supabase SQL Editor as project owner. It does not turn maintenance off.
- `supabase/game_online_v2.sql`: just the incremental migration; use this only after the foundation is already installed.
- `dtp/src/com/destian/dtp/SupabaseGameBackend.java`: Java HTTPS adapter for Supabase Auth, profile/avatar ID, player search, friend requests, presence, player-save sync, rankings, World Boss boards/claims, PvP queue/history.
- `supabase/functions/game-online/index.ts`: operator-only review endpoint for official competitive results. Configure `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `KIC_SCORE_REVIEW_KEY` as server-side secrets; never ship them in the APK.

### Source inspection / hard limitation

The game is still built around a precompiled native `libgame.so`; its original C++ source for the old `NetworkManager` login/PvP/World Boss calls is not included. The Supabase adapter is **not yet called by the original native game screens for those legacy online flows**. In v16, a separate JNI bridge now calls verified exported wallet functions in this supplied library to apply only admin-edited Coins, Crystals, and Goblin Coins on the Cocos GL thread. This does not reconnect the original login/PvP/World Boss screens or all player stats. A native Cave Boss combat scene/assets were also not present; the Cave Boss RPC currently drives an in-game event-status banner only.

### Feature behavior and security

- **Diperbarui pada v17.13:** autentikasi pemain memakai Google secara langsung. Google memverifikasi email; tidak ada password atau konfirmasi password game. Supabase Auth hanya dipakai untuk akun admin dashboard.
- Profile/avatar changes save the original game's numeric `avatar_id` so the selected avatar can be drawn from bundled game assets; this adapter does not upload arbitrary avatar images.
- Friends/search/requests and presence use authenticated RPCs and RLS.
- Player save sync is supported, but client-supplied save data is not trusted for competitive scores or premium currency.
- Ranking and World Boss boards are read-only for normal clients. A World Boss score from the APK is stored as a **pending claim** and does not become an official score until a trusted reviewer/verifier approves it.
- PvP queue can pair two authenticated players and create an in-progress match record. It does not simulate or transmit the native C++ battle itself. A trusted verifier must review the battle/replay before the match is marked complete and the winner is counted.
- The service-role key and review secret must only exist in Supabase/server secrets. Never paste them into Java source, SQL sent to a user, or APK resources.

### Test and build

Run source checks:

```bash
python3 -m pytest -q tests
```

The current working environment has no Android SDK, NDK, `android.jar`, or `apktool.jar`, so APK compilation/signing and device runtime cannot be verified in this session. `build_dtp.py` now requires Android NDK `27.2.12479018` to compile `libkicgamebridge.so` for `armeabi-v7a`; the GitHub Actions workflow installs it. A configured CI build and actual device test remain required.

## Java Online Hub update (v9)

The Java Supabase adapter is compiled into the DTP APK by `build_dtp.py`. This update adds a small **ONLINE** button over the game Activity and a separate `GameOnlineHubActivity` that calls the adapter for:

- Supabase signup/login/logout and profile/avatar-ID updates;
- player search, friend requests, friends list and incoming requests;
- leaderboard reads and online-presence heartbeat;
- PvP queue/history calls exposed by the SQL API;
- World Boss active cycles, rankings and pending score claims.

The hub runs HTTPS requests off the UI thread. The online button is installed by `DtpApp` only while `com.droidhang.ph.GameActivity` is active. The added activity is internal (`exported=false`).

**Important limits:** this is a Java online hub plus a narrow JNI wallet bridge, not a restoration of every legacy screen. Only the three supported currency fields are pushed into the live native wallet; XP/levels/energy/stamina/honor/arena/skill points, full native save round-trip, original PvP battle execution, and trusted World Boss reward delivery remain incomplete. World Boss scores submitted by the client remain pending until a trusted server operator verifies them.

Build with `python3 build_dtp.py` after installing JDK 17+, Android SDK build-tools/platform, and `tools/apktool.jar`. This environment's source ZIP does not include `tools/apktool.jar`, and no Android SDK path was configured during this edit, so a final APK was not built or installed here. Apply `supabase/game_online_v2.sql` (or the project's documented complete migration sequence) to the intended Supabase project before testing the online hub.


---

## v17.1 Realtime SQL/TypeScript hardening

- The current single-file Supabase setup is `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.2-ALL-IN-ONE.sql`.
- The incremental Event Shop migration is `supabase/migrations/202611260006_event_store_v17.sql` (unique migration version).
- Event Shop config/catalog now publish authenticated Postgres Changes; Android subscribes by WebSocket, with a 1-second fallback for time-window changes and reconnects (v17.2).
- Run checks with `pytest -q tests`; `deno check supabase/functions/game-admin/index.ts` should be run in a connected Deno environment before deployment.

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

## Admin Data Pemain (v11)

Panel admin yang sebelumnya hanya mengatur maintenance kini tersedia di `admin.html` dengan tambahan halaman Manajemen Data Pemain. Migrasi database ada pada `supabase/migrations/202611260003_admin_player_management.sql`, bootstrap admin ada pada `supabase/admin-bootstrap.sql`, dan Edge Function ada di `supabase/functions/game-admin/index.ts`.

Baca `ADMIN-PLAYER-MANAGEMENT.md` untuk langkah pemasangan, whitelist akun admin, deployment Edge Function, dan batas integrasi save native. Jangan pernah meletakkan Supabase `service_role` key di file HTML atau APK.

## Bahasa Indonesia (v12)

Source terbaru memproses **2.254 entri teks game** ke Bahasa Indonesia. Detail cakupan, cara build, placeholder QA, dan batasan tersedia di [`BAHASA-INDONESIA-README.md`](BAHASA-INDONESIA-README.md) dan [`CHANGELOG-INDONESIA-V12.md`](CHANGELOG-INDONESIA-V12.md). File runtime yang digunakan native sekarang adalah `assets/public/config/string/de.xml` karena enum native hanya menyediakan lima slot bahasa; file kanonis `assets/public/config/string/id.xml` juga disertakan. Oleh karena itu, bahasa Deutsch digantikan pada build ini. Teks di dalam gambar/tekstur dan string hardcoded `libgame.so` belum termasuk. APK final belum dibangun pada sesi ini.


# Strict realtime/maintenance recovery v15

## What changed
- Maintenance gate now fails closed: network errors, missing/duplicated config row, or missing `is_active` no longer imply maintenance is OFF. The maintenance screen cannot be dismissed to return to the game's Activity, and the running game process is stopped when the server turns maintenance ON or cannot be verified.
- SQL v15 adds a server-side maintenance predicate, RLS restrictions on player-facing reads, and write triggers that reject authenticated player data changes while maintenance is active. The trusted `service_role` admin Edge Function remains available for repairs/toggles.
- Realtime remains the push path for maintenance with a short polling safety-net. No network implementation can promise zero-millisecond delivery; push latency depends on connectivity and server scheduling.
- When a Supabase Auth session exists, Android subscribes with that user's JWT to their own `game_profiles`, `game_player_saves`, and `game_admin_player_economy` rows. Events trigger a fresh `get_my_game_runtime_state()` snapshot stored in app-private preferences. The Online Hub can also fetch and display a current snapshot.
- The v14 all-in-one SQL and v12 game-admin Edge Function are included in this project. Deploy the Edge Function and apply the SQL before expecting remote admin changes.

## Offline vs strict maintenance
A strict, non-bypassable server maintenance gate and unrestricted offline gameplay cannot both be guaranteed. An offline device cannot learn instantly that the server has switched maintenance ON. This build chooses safety: if the maintenance status cannot be verified, the game is blocked. Offline local gameplay is therefore not enabled by this strict gate. Supporting it would require an explicit admin policy and bounded offline lease, which necessarily creates a short period during which a disconnected device cannot receive a new maintenance command.

## Native gameplay scope — updated by v16
The v15 statement above is superseded for three wallet fields only: v16 now applies admin-edited Coins, Crystals, and Goblin Coins to exported native `LevelManager` methods through a JNI bridge. Each currency has its own admin revision so untouched local balances are not overwritten. This bridge has not yet been built/tested on a device in this session. XP, levels, energy, stamina, honor, arena tokens, skill points, cloud-save round-trip, native PvP, and World Boss reward delivery remain incomplete. Cave Boss displays the server event banner but does not spawn a native enemy or battle scene.

## Deploy and build
1. For a fresh project, apply `supabase/kingdom-in-chaos-dtp-SQL-SUPER-LENGKAP-ALL-IN-ONE-v16-CAVE-BOSS-NATIVE-BRIDGE.sql`. For a project already on v15, follow the two incremental migration files listed in the v16 section below.
2. Set server-only secrets and deploy `supabase/functions/game-admin/index.ts` as function `game-admin`. Never embed `service_role` in APK or HTML.
3. To deploy the matching maintenance Admin endpoint, set `MAINTENANCE_ADMIN_NAME` and `MAINTENANCE_ADMIN_PASSWORD`, optionally `ADMIN_ALLOWED_ORIGINS`, then run `supabase functions deploy maintenance-admin`. It invokes the transactional `admin_update_app_maintenance` RPC so the row update and maintenance history insert commit together.
4. Run `python3 -m pytest -q tests`.
5. Build APK only in an environment with JDK, Android SDK (including android.jar/build-tools), and `tools/apktool.jar`: `python3 build_dtp.py`.
6. Live-test: maintenance ON while playing, maintenance OFF, disconnected connection, missing config row, and admin economy/profile/save edits using two authenticated accounts.


---

# v16 — Cave Boss + Native Currency Bridge (26 November 2026)

## Paket dan cakupan
- Panel admin v16: `admin.html`. Edge Function: `supabase/functions/game-admin/index.ts`.
- SQL gabungan: `supabase/kingdom-in-chaos-dtp-SQL-SUPER-LENGKAP-ALL-IN-ONE-v16-CAVE-BOSS-NATIVE-BRIDGE.sql`.
- Android bridge: `dtp/src/com/destian/dtp/NativeGameRuntimeBridge.java`, `NativeGameRuntimeSync.java`, dan `dtp/native/game_runtime_bridge.cpp`.
- Wallet native: hanya Coins, Crystals, Goblin Coins. Revisi setiap kolom disimpan terpisah dan per `user_id`; saldo lokal lama tidak diubah sampai field tersebut diedit admin.
- Cave Boss: pembacaan `get_active_cave_boss()` dan banner dalam game. Enemy spawn/AI/scene/reward belum tersedia dalam source native yang diberikan.

## Deploy Supabase
Untuk pemasangan penuh/proyek baru, jalankan SQL v16 all-in-one di SQL Editor. Untuk proyek yang sudah menjalankan v15, jalankan `supabase/migrations/202611260004_cave_boss_v16.sql`, lalu `supabase/migrations/202611260005_native_economy_revision_bridge_v16.sql`. Deploy ulang Edge Function `game-admin`. Jangan pernah memasukkan `service_role` ke browser/APK.

## Build
Perlu JDK 17+, Android SDK platform 35, build-tools 35.0.0, NDK 27.2.12479018, dan `tools/apktool.jar`. Jalankan `python3 -m pytest -q tests` lalu `python3 build_dtp.py`. GitHub Actions menginstal SDK/NDK dan membuat artifact APK. APK belum dibangun atau diuji pada perangkat dalam sesi penggabungan ini.

Baca `CHANGELOG-V16-CAVE-BOSS-NATIVE-BRIDGE.md` untuk batas fitur dan daftar uji wajib.


## v17.2 — Event Shop polling + SQL gabungan

- Event Shop fallback polling is now 1 second in the game overlay and Event Shop screen.
- The single canonical All-in-One SQL is `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.2-ALL-IN-ONE.sql`; an identical copy is under `supabase/`.
- For new projects, run that single file only. For an existing v16 project, run only migration `supabase/migrations/202611260006_event_store_v17.sql` after its v15/v16 prerequisites.
- Cave Boss fallback remains 15 seconds; maintenance check remains 2 seconds.

## v17.3 TypeScript Realtime
- Deploy the updated `supabase/functions/game-admin/index.ts` Edge Function.
- Existing v17.2 databases must run `supabase/migrations/202611260007_player_event_realtime_v17_3.sql`.
- New databases use `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.3-ALL-IN-ONE.sql`.
- Event Shop updates use Broadcast invalidation plus Postgres Changes; player profile/save/economy updates use per-player Broadcast topics plus Postgres Changes.
- Android keeps the 1-second polling fallback; successful Realtime pushes cause an immediate authenticated RPC refresh.


## v17.6 — Google Auth untuk akun game (26 November 2026)

Pembaruan ini menambahkan login Google melalui Supabase Auth dengan Authorization Code + PKCE:

- Deep link callback Android: `kingdominchaosdtp://auth`.
- Layar autentikasi memakai ikon game dari resource `@drawable/icon`; tidak memakai logo Google.
- Judul layar: **Login ke Kingdom In Chaos DTP**.
- Tombol `LOGIN` / `AKUN` pada overlay game membuka login Google atau Online Hub sesuai status sesi.
- Token akses dan refresh Supabase disimpan terenkripsi menggunakan Android Keystore, melanjutkan mekanisme penyimpanan sesi yang sudah ada.
- Fitur akun/avatar, teman, ranking, presence, PvP dan World Boss di Online Hub meminta login bila belum ada sesi. Login email lama tetap disediakan sebagai alternatif.

### Konfigurasi Supabase yang wajib

1. Dashboard Supabase → Authentication → Providers → Google: aktifkan Google dan masukkan **Web OAuth Client ID** serta **Client Secret** dari Google Cloud.
2. Google Cloud → OAuth Client (Web application): Authorized redirect URI harus menggunakan callback Supabase project, yaitu `https://gunzwimrxspbmiducphg.supabase.co/auth/v1/callback`.
3. Supabase → Authentication → URL Configuration → Redirect URLs: tambahkan persis `kingdominchaosdtp://auth`.
4. Simpan dan uji login pada APK yang dibangun dari source versi ini.

Jika Google Provider belum aktif atau Redirect URL belum diizinkan, proses login akan gagal dan aplikasi menampilkan pesan dari Supabase.

### Batas integrasi UI native

Tombol akun/login Android ditambahkan sebagai pintu masuk ke autentikasi. Source C++ untuk layar asli game tidak tersedia dalam paket ini, sehingga sentuhan langsung pada tombol avatar/menu online bawaan native belum dapat dialihkan satu per satu ke layar login. Operasi online yang tersedia melalui Java Online Hub sudah meminta sesi terlebih dahulu; ini bukan klaim bahwa seluruh layar online C++ lama sudah tersambung.

Build memakai workflow GitHub Actions atau `python3 build_dtp.py` pada lingkungan yang sudah memiliki JDK, Android SDK, Android NDK dan apktool. ZIP ini berisi source yang diperbarui, bukan APK yang sudah dibangun dan diuji di perangkat.


## v17.13 — Google Direct Auth, Kode Hadiah, dan Daging (27 November 2026)

Versi ini mengganti autentikasi pemain dari alur Supabase OAuth lama menjadi login langsung melalui akun Google Android. Lihat `CHANGELOG-V17.13-GOOGLE-DIRECT-REWARDS-MEAT.md` dan `GOOGLE-AUTH-SETUP-v17.13.md` untuk alur, konfigurasi, dan batas integrasi.

- Pemain masuk dengan tombol berikon Google; tidak ada password atau konfirmasi password game. Email harus memiliki klaim `email_verified=true` dari Google.
- Pemain baru wajib menyelesaikan Tahap 2 dengan memilih nickname 3–32 karakter; server mengeluarkan Player ID unik.
- `admin.html` otomatis menampilkan daftar akun Google beserta email, avatar, ID pemain, nickname, Koin, DM, Daging, dan status verifikasi.
- Admin dapat membuat dan menyalin kode hadiah serta mengatur reward, kuota, dan tanggal berlaku.
- Makanan/Life native: kapasitas bawaan 24; `lifeRecoveryInterval` sudah diubah menjadi 300 detik (+1 setiap 5 menit). Pembelian native bawaan tetap 12 makanan seharga 50. Daging Cloud untuk admin/kode hadiah terpisah dari Life native.
- SQL baru: `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.13-GOOGLE-AUTH-KODE-DAGING.sql`; Edge Functions: `google-player` dan `game-admin`.

**Batas integrasi:** stage memakai gate Makanan/Life bawaan `libgame.so`; konfigurasi regen diperbarui tetapi perlu uji runtime APK. Daging Cloud dan wallet DM/Koin cloud masih terpisah dari nilai native. APK belum dibangun/diuji di perangkat. Detail dan langkah deploy ada di changelog v17.13.

## v17.14 — Surat and native wallet monitoring

Admin reward delivery now uses the in-game Surat inbox. The player receives the letter, presses Klaim, and the server credits the cloud reward ledger once. The Android client then applies the reward through the native game wallet APIs on the Cocos GL thread and records a local retry journal. The admin dashboard shows read-only native wallet snapshots uploaded every 10 seconds while the game is foreground, with Realtime Broadcast and 15-second refresh fallback. This is near-realtime, not a guarantee of 100% instant delivery. See `CHANGELOG-V17.14-MAIL-CRASHFIX.md` and `VERSION-v17.14-MAIL-CRASHFIX.txt`.
