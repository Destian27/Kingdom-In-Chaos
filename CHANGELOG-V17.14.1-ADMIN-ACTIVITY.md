# v17.14.1 — activity feed and wallet freshness

- Fixed GitHub Actions artifact path to match the APK produced by `build_dtp.py` (`KingdomInChaosDTP-v17.14-mail-crashfix.apk`).
- Admin dashboard selects the newest available wallet source by timestamp; a stale native snapshot no longer masks a fresh claimed-Surat server balance.
- Dashboard displays Google avatar and native game avatar ID.
- Added a server-side activity ledger for meaningful Google player actions and admin mail/reward-code actions. No access token or password is recorded.
- Activity and player tables refresh via Supabase Broadcast, with a 15-second polling fallback. Wallet snapshots are observations supplied by the client and are not cryptographically authoritative.
- The admin has no direct currency-edit operation; rewards are credited by the server only after the player claims the Surat or a valid reward code.
