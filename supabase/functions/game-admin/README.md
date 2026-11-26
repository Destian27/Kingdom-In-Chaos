# game-admin Edge Function — v16

Secure server endpoint used by v16 `admin.html` for player search, account details, profile editing, economy editing, cloud-save editing, Cave Boss hourly schedules/manual override, and audit history.

## Deploy

```sh
supabase functions deploy game-admin
```

The runtime must have `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` configured as server-side environment/secrets. Never place the service-role key in HTML, Java, an APK, or a public repository.

## Access model

Every request must carry a valid Supabase Auth access token. The function resolves the user through Supabase Auth and requires an active row in `public.game_admin_users`. Database writes use the service-role key only inside this function.

## v16 actions

- `whoami`, `list_users`, `get_user`
- `update_profile`, `update_economy`, `update_save`, `list_audit`
- `cave_boss_get`, `cave_boss_save_schedule`, `cave_boss_trigger`, `cave_boss_clear`, `cave_boss_logs`

All admin economy edits require a reason and are written with audit records. Admin edits to Coins, Crystals, and Goblin Coins create individual currency revisions; Android v16 applies those revisions through the native wallet bridge. Other economy stats remain backend-only.


## v17.3 Realtime Broadcast

The Edge Function emits invalidation-only Supabase Realtime Broadcast events after admin writes:

- `event_store_updated` on topic `realtime:event-store`.
- `player_state_updated` on topic `realtime:player-state-<user UUID>` after economy, profile, or cloud-save edits.
- `cave_boss_updated` on topic `realtime:cave-boss` after schedule or override edits.

The Android client reloads the current authenticated RPC snapshot after receiving a Broadcast. Postgres Changes is also enabled by the SQL publication; polling remains only as a fallback.
