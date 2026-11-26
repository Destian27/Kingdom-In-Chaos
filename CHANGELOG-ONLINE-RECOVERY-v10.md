# Kingdom In Chaos DTP — Online Recovery v10

## Added
- Recovery SQL v3: cloud-save history table/trigger, PvP match state RPC, stale-queue cleanup and reconciliation, audited server-side review RPCs.
- Hardened `game-online` TypeScript review gateway: request size cap, UUID validation, CORS allowlist option, explicit human confirmation/note, pending review listings, and generic public database errors.
- Java adapter method + Online Hub input to inspect a match's server-side state.

## Verification status
- Package-level source checks are run after this change.
- SQL has not been applied to the user's live Supabase project, and no live database execution is claimed.
- The native game C++ battle engine and original online HTTP API source are not present, so native PvP battle simulation and original cloud-save/reward integration are still blockers. This package is not honestly describable as 100% restored.
