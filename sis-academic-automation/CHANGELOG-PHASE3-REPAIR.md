## Phase 3 secret-scan repair

### Fixed

- Excluded local-only `.env` from the Phase 3 portable secret scan.
- Excluded local-only `portal/config.local.js`.
- Kept `.env.example`, `portal/config.example.js` and all portable files under secret scanning.
- Added a regression test that preserves and restores the user's existing `.env`.

### Impact

- No secrets were exposed.
- No database or Google Workspace asset was changed.
- Phase 3 provisioning can continue after the validator passes.
