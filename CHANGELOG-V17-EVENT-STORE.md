# Kingdom in Chaos DTP — v17 Event Shop

## Added
- Supabase Event Shop configuration with one-time, daily, and weekly schedules evaluated in Asia/Jakarta (WIB).
- Event item catalogue: item key/name, description, HTTPS image URL, Mata Event price, optional native item ID, JSON payload, visibility, and ordering.
- Admin controls to enable/disable the shop, set start/end/repeat-until time, configure refresh interval, and save an item list.
- Player-specific `event_eyes` balance with a dedicated admin save action that does not edit Coins, Crystals, or Goblin Coins.
- Native Mata Event bridge: `FestivalActivityScorePoint` uses the game's original `UserDataType 0x85`; the JNI bridge reads/writes that same key via `UserDataManager` on the Cocos GL thread and confirms the final balance. Native range: 0–2,147,483,647.
- Android Event Shop screen in landscape with server-driven item cards, native-backed eye balance, end time, and server-derived refresh countdown. An `EVENT SHOP` entry appears over the native game only while the server schedule is active.

## Realtime hardening (v17.1)
- Event Shop config and catalogue tables now have authenticated read-only RLS policies and are added to `supabase_realtime` with `REPLICA IDENTITY FULL`.
- Android game overlay and the Event Shop screen subscribe to both tables through authenticated WebSocket channels. The fallback poll now runs every 1 second (v17.2) for schedule/reconnect detection.
- Player economy changes remain subscribed to `game_admin_player_economy`; coalesced refreshes prevent a burst of row events from losing the final state.
- The migration uses unique version `202611260006` (the previous `004` collided with the Cave Boss migration).

## Important integration boundary
The shop's event schedule, title, banner, item list, item art, price labels, and Mata Event balance are connected to the Supabase-backed Android client. Admin edits to Mata Event are applied to the original game's native currency key, not only the database.

Actual purchase/delivery of the configured items into the original native inventory is not enabled yet. `native_item_id` is retained as mapping metadata until the original inventory transaction path is integrated and tested. The overlay also does not replace every original native Halloween popup or scene.

## Deployment
1. On an existing v16 Supabase project, run `supabase/migrations/202611260006_event_store_v17.sql` after the v15/v16 prerequisites. For a fresh project, run `supabase/kingdom-in-chaos-dtp-SQL-SUPER-LENGKAP-ALL-IN-ONE-v17-EVENT-STORE.sql`.
2. Deploy `supabase/functions/game-admin/index.ts` as the `game-admin` Edge Function. Keep the service-role key in Edge Function secrets, never in the APK.
3. Host `admin.html` with the same static hosting setup as the existing admin page. Ensure the operator is registered in `game_admin_users`.
4. Build and sign a new APK with `.github/workflows/build-apk.yml` (or `python3 build_dtp.py` in an Android SDK/NDK environment). This ZIP contains source, not a prebuilt APK.
5. In Admin > Manajemen Data Pemain, edit `Mata Event` using **Simpan Mata Event saja**. In Admin > Event Shop, add catalogue items and set start/end/repeat schedule.
6. Log in to Supabase from the game using ONLINE. During an active schedule, the `EVENT SHOP` button appears in the game overlay.
