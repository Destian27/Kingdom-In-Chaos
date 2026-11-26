# Deployment v17.3 — TypeScript Realtime

## Existing database already on v17.2
1. Run `supabase/migrations/202611260007_player_event_realtime_v17_3.sql` in Supabase SQL Editor.
2. Deploy `supabase/functions/game-admin/index.ts` as Edge Function `game-admin`.
3. Build and install the Android project from this ZIP.

## New database
Run `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.3-ALL-IN-ONE.sql` once, then deploy the Edge Function and build the APK.

## Realtime topics
- `realtime:event-store`: Event Shop catalog/config invalidation.
- `realtime:player-state-<user UUID>`: targeted player state invalidation.
- `realtime:cave-boss`: Cave Boss schedule/override invalidation.

The Broadcast contains only invalidation metadata. Android reloads data with authenticated RPC calls. Postgres Changes is also published for the relevant tables. Event Shop retains a 1-second polling fallback; Cave Boss retains its existing 15-second polling fallback.

Realtime delivery needs an active Supabase project with the `supabase_realtime` publication enabled, deployed Edge Function secrets, authenticated clients, and a built APK. It has not been live-tested against the user's Supabase project in this workspace.
