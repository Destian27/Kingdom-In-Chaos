# Kingdom in Chaos DTP — Realtime and strict maintenance v15

- Strict fail-closed maintenance: any missing or unverifiable maintenance configuration blocks entry rather than allowing a bypass.
- Realtime client supports authenticated multi-table subscriptions filtered to the current user's UUID.
- Admin changes to profile, cloud save, and economy trigger a fresh runtime snapshot and update private app cache.
- Online Hub adds a snapshot refresh for server-backed Coins/Crystals/XP/save state.
- All-in-one v14 SQL and admin Edge Function copied into the game source package.

## Not claimed
- Zero latency cannot be guaranteed; Realtime is push-based with polling fallback for maintenance.
- Current native game HUD/local save are not wired to the cached snapshot because original C++/save serialization source is absent.
- Offline gameplay conflicts with an absolute maintenance gate; this version fails closed when server status cannot be checked.
- SQL/Edge Function have not been applied/deployed to the user’s live project; APK not built in this environment.

- Added a bundled `maintenance-admin` Edge Function matching the existing Admin HTML API; save action calls an atomic SQL RPC that also writes maintenance history.
- Added server-side RLS read restrictions and DML triggers so standard authenticated player requests are blocked while maintenance is active; trusted service-role admin changes remain available.
