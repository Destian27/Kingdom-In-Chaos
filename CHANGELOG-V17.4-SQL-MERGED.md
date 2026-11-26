# v17.4 — SQL merged and strict Realtime preflight

- Added one canonical all-in-one SQL file containing migration 007 Realtime publication/replica identity operations.
- Added fail-fast preflight for missing `supabase_realtime` before schema changes.
- Realtime module now errors clearly when any required player/event table is absent instead of silently skipping it.
- Preserved incremental migration 007 for existing v17.2 databases; do not run it separately when the full v17.4 bundle has already run.
- Kept TypeScript v17.3 Realtime and Android one-second fallback polling unchanged.
