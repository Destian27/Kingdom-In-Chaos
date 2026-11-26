# Kingdom in Chaos DTP — v17.1 Realtime and SQL hardening

## Fixed
- Event Shop configuration and item catalogue now grant authenticated read-only access under explicit RLS policies.
- Both Event Shop tables are added to the `supabase_realtime` publication and use `REPLICA IDENTITY FULL`.
- Android subscribes to the shared Event Shop tables using a dedicated unfiltered WebSocket channel in the game overlay and Event Shop screen.
- Android now marshals Realtime callbacks onto the main thread and coalesces overlapping fetches so a burst of table changes cannot leave stale data as the final screen state.
- Player economy snapshot refreshes also coalesce overlapping realtime notifications.
- TypeScript strict-mode errors from implicit `any` callback parameters are fixed; Event Shop item input receives server-side validation before the SQL RPC.
- Fractional prices are rejected rather than rounded to integer balances, and the native Event Eyes upper bound is checked explicitly.
- Event Shop migration version moved from `202611260004` to `202611260006` because `202611260004` was already assigned to the Cave Boss migration.

## Checks run in this package
- Python tests: 58 passed, 2 skipped.
- TypeScript `tsc --strict --noEmit`: passed using a local Deno/Supabase ambient shim because network access is unavailable.
- Admin HTML JavaScript: `node --check` passed.
- Native JNI C++ source: Clang syntax-only check passed with the installed JDK JNI headers.
- SQL lexical/static check: passed; 419 top-level statements, balanced transaction markers and dollar-quoted blocks, all policies recreated idempotently, Event Shop grants/policies/publication present.

## Not claimed as verified
The SQL has not been executed against the user's live Supabase project or an actual PostgreSQL server in this environment. Deno's remote Supabase package types could not be fetched offline, and the APK has not been built or run on a device. Apply the SQL to a staging Supabase project and confirm the migration result and Realtime connection before production use.
