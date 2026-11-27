# v17.14.2 — Admin read-only, in-game mail, and crash-guard packaging

- Removed the legacy second Supabase Auth login panel from the player-management page. The data panel uses the existing primary admin session.
- Removed legacy direct player edit controls and routes for editing profile, currency/economy, and cloud saves. The admin dashboard is observational; player rewards are delivered through in-game Surat.
- Admin sends a message/reward to a verified Google player's in-game mailbox. Sending does not credit a wallet; the server credits once when the player claims the mail.
- Admin player rows prefer the fresher of the server-updated economy row and the observed native-wallet snapshot. Realtime Broadcast plus a 15-second polling fallback refreshes players, mail, and activity.
- The Android app captures native wallet values every 10 seconds while the game is foregrounded. These are client-observed snapshots, not anti-cheat authoritative values.
- Preserved the `LifeMax()` ARM patch for the reported `UIAchieveLayer::onAward()` crash and retained the 24-food ceiling / 5-minute recovery setting.
- Bumped Android package metadata to versionName `17.14.2`, versionCode `12`; aligned the build script and GitHub Actions artifact names.

## Verification

- Source tests: 94 passed, 2 skipped (APK integration checks).
- Admin inline JavaScript syntax checked with Node.
- `LifeMax()` patched bytes checked in both ARM ABIs and disassembly verified as `movs r0, #24; bx lr`.
- APK build and on-device behavior are not verified here because this environment does not have Android SDK build-tools, NDK, or apktool installed.

- Updated the in-game Online Hub explanation to remove obsolete claims about direct admin wallet editing and clearly distinguish the Google profile picture from the original game's local character avatar.
- Google email, verification, display name, and Google profile photo are refreshed on each verified player API request; foreground wallet sync triggers this about every 10 seconds and broadcasts a dashboard refresh.
