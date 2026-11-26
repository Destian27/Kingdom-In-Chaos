# v17.2 — One-second Event Shop Poll + Single SQL

- Event Shop fallback polling on the in-game overlay changed from 15 seconds to 1 second.
- Event Shop screen state polling and its refresh-boundary retry changed to 1 second.
- Supabase Realtime remains the push path; this polling is a safety net and also detects schedule boundaries.
- Maintenance polling (2 seconds), Cave Boss fallback (15 seconds), WebSocket read timeout and reconnect backoff were not changed.
- SQL is now distributed as one canonical All-in-One file: `kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.2-ALL-IN-ONE.sql`, with an identical copy under `supabase/`. It contains the complete v15 + strict maintenance + v16 Cave Boss + economy bridge + v17 Event Shop SQL sequence.
- Incremental install for an existing v16 project remains migration `202611260006_event_store_v17.sql` only.
