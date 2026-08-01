## Phase 3 regression-fixture repair

### Fixed

- Removed the complete fake server-key literal from the portable regression script.
- Constructed the synthetic probe value from fragments at runtime.
- Preserved the positive test proving that portable secret-shaped values are rejected.
- Preserved cleanup and final-pass verification.

### Impact

The production secret scanner remains strict. No real secret, database object or Google Workspace asset was changed.
