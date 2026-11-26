# Kingdom In Chaos DTP — Java Online Hub v9

## Added
- `GameOnlineOverlay.java`: a small in-game ONLINE button, installed only while the original `GameActivity` is active.
- `GameOnlineHubActivity.java`: a standalone Android screen that calls the existing `SupabaseGameBackend` adapter for account, profile/avatar ID, friends, rankings, presence, PvP queue/history, and World Boss score claims.
- Manifest registration for the internal online hub and lifecycle wiring in `DtpApp.java`.
- Static integration test for the new route from the game into the hub.

## Verified
- Source tests: 28 passed, 2 skipped.
- The adapter class in the uploaded ZIP was byte-for-byte identical to the separately uploaded Java file.

## Not verified / limitations
- No Android SDK or `tools/apktool.jar` was available in the current environment, so no final APK was built or installed.
- This is a Java online hub separate from the legacy native screens. The original C++ source and call sites for the old native HTTP/PHP client are not present in this source tree, so those native screens are not automatically redirected to Supabase.
- PvP matchmaking does not simulate native battle; World Boss score claims remain pending until trusted server verification; the original game save/reward/currency flow is not integrated with cloud save.
