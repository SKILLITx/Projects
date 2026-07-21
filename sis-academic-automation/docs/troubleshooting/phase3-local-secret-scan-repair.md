# Phase 3 Local Secret-Scan Repair

## Failure

`Test-Phase3Package.ps1` scanned the local `.env` file and correctly detected that it contained a secret-like value. However, `.env` is intentionally a local-only runtime file and is already excluded from the portable repository contract.

## Root cause

The Phase 3 validator excluded generated directories such as `node_modules`, `.runtime` and `.git`, but did not exclude:

- `.env`
- `portal/config.local.js`

Those two files are allowed to contain locally entered configuration and must never be packaged, committed or copied into portable artifacts.

## Repair

The validator now:

1. excludes `.env`;
2. excludes `portal/config.local.js`;
3. continues scanning `.env.example`, `portal/config.example.js`, scripts, documentation and all other portable project files;
4. reports secret findings specifically as portable-file failures.

No secret value is read, printed or copied by the repair.

## Regression

`Test-Phase3SecretScan.ps1` temporarily writes a fake local-only secret into `.env`, runs the complete Phase 3 validator, and restores the original `.env` without displaying it.
