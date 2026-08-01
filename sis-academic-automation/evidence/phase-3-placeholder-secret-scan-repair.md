# Phase 3 Placeholder Secret-Scan Repair Evidence

- Failing layer: static secret scanner.
- Failed file: `.env.example`.
- Incorrect state: placeholder value classified as a real service-role key.
- Secret exposure: none.
- Repair: placeholder-aware environment assignment validation.
- Portable examples remain scanned.
- Local `.env` and `portal/config.local.js` remain excluded.
- Regression includes a fake `sb_secret_...` probe that must be detected and removed.
