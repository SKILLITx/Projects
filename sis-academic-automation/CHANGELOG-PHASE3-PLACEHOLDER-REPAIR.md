## Phase 3 placeholder-aware secret scan

### Fixed

- Replaced the service-role length heuristic with placeholder-aware assignment parsing.
- Kept `.env.example` inside the portable scan.
- Added detection for Supabase `sb_secret_...` keys.
- Added a positive regression proving that a secret-shaped portable value is rejected.
- Kept local `.env` and `portal/config.local.js` excluded.

### Impact

No project secret was printed, copied or changed. Google Workspace provisioning has not started and can continue after the validator passes.
