# v17.3 — TypeScript Realtime Broadcast

- Edge Function `game-admin` emits a minimal `event_store_updated` Broadcast after Event Shop save.
- Economy, profile, and cloud-save admin updates emit `player_state_updated` to the matching user's topic.
- Cave Boss schedule save, manual trigger, and clear operations emit `cave_boss_updated`.
- Broadcast payloads contain invalidation metadata only; clients reload authenticated RPC snapshots.
- Android RealtimeClient dispatches Broadcast events as well as Postgres Changes.
- Event Shop screens share `realtime:event-store`; player state uses `realtime:player-state-<user UUID>`; Cave Boss uses `realtime:cave-boss`.
- SQL publishes profile, cloud-save, admin-economy, Event Shop, and Cave Boss tables with REPLICA IDENTITY FULL.
- Polling remains a 1-second Event Shop fallback and a 15-second Cave Boss fallback; neither is the primary update path.

## Deployment

1. Existing v17.2 database: run `supabase/migrations/202611260007_player_event_realtime_v17_3.sql`.
2. Deploy the updated `supabase/functions/game-admin/index.ts` as Edge Function `game-admin`.
3. Build and install the updated Android APK.
4. Test with two signed-in clients: save Event Shop, update a player's economy, and change Cave Boss schedule; verify the relevant views refresh.

Realtime Broadcast is best-effort; Postgres Changes and polling fallbacks remain enabled. Live delivery still requires the deployed Supabase project to have the `supabase_realtime` publication enabled.
