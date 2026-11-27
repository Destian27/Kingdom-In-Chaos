# v17.14 — Surat, wallet snapshot, and LifeMax crash guard

- Corrected reward delivery: admin sends a Surat to the in-game inbox, using the Google email only to identify the target player. No email is sent.
- The server credits cloud Koin, DM, Goblin, and meat only when the matching Google player claims a mail. The SQL claim locks the mail row and rejects a second claim.
- After claim, the Android client queues the mail reward and applies monotonic native wallet targets on the Cocos GL thread. Coins, DM, Goblin Coins, and Life are updated through the original `libgame.so` APIs. A persistent local journal supports retry/recovery.
- Admin cannot directly set player balances. The dashboard uses the existing maintenance-admin login session and sends rewards by Surat.
- Android reads the live native wallet on the GL thread and sends a read-only snapshot to a service-role-only table every 10 seconds while the game is foreground. The admin page displays the latest native snapshot, broadcasts refresh events, and polls every 15 seconds as fallback.
- The crash report identifies `UIAchieveLayer::onAward -> LifeMax()+60` as the native SIGSEGV path. The exact checked ARM patch replaces the LifeMax entry with `movs r0,#24; bx lr` for both bundled ARM ABI libraries. This is a targeted workaround for the current binary and assumes the game life cap is 24; it must be tested on the target device.
- Realtime is best-effort while connected; the 10-second snapshot interval and 15-second fallback are not a promise of 100% instant delivery.
- Automated tests: 94 passed, 2 skipped in the current workspace. Native C++ syntax and admin JavaScript syntax were checked. APK/device execution was not available in this environment.
