# Result review endpoint (server-side only)

The APK must never call an admin review endpoint and must never contain the Supabase `service_role` key.

The SQL migration provides server-only RPCs to approve PvP and World Boss results. They are intended to be called only after the match/replay has actually been verified by a trusted reviewer or replay verifier. The old game's native replay format and scoring algorithm are not available as editable C++ source in this repository, so this package does not claim automatic anti-cheat verification.

For now, World Boss claims remain `pending` and do not affect the official ranking until an administrator approves them. PvP matches remain `in_progress` until a trusted verifier approves a participant's result. The Java game adapter deliberately cannot call these admin RPCs.

Configure any review tool with server-only credentials using Supabase Edge Function secrets or a protected server environment; do not put them in `MaintenanceActivity.java`, `SupabaseGameBackend.java`, the Android APK, or a public GitHub repository.
