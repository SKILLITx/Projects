# Phase 3 Placeholder-Aware Secret Scan Repair

## Failure

The previous repair correctly excluded local `.env`, but the portable `.env.example` still failed because this placeholder was treated as a real secret:

```text
SUPABASE_SERVICE_ROLE_KEY=REPLACE_SERVER_SIDE_IN_PHASE_2
```

## Root cause

The first validator used a length-based regular expression. Any long value assigned to `SUPABASE_SERVICE_ROLE_KEY` was treated as secret material, including explicit placeholders.

## Repair

The validator now:

- continues excluding local `.env`;
- continues excluding local `portal/config.local.js`;
- scans `.env.example` and all other portable files;
- accepts empty values and explicit placeholders beginning with values such as `REPLACE`, `YOUR`, `GENERATED`, `SET`, `EXAMPLE`, `PLACEHOLDER`, `INSERT`, `ADD` or `CONFIGURE`;
- detects Supabase `sb_secret_...` keys;
- detects non-placeholder values assigned to known secret variables;
- detects Google API keys and private-key headers.

The `.env.example` file is not excluded. It remains scanned and passes only because it contains documented placeholders rather than credentials.
