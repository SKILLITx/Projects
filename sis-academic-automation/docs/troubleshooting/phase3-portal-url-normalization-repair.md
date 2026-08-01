# Phase 3 Portal URL Normalization Repair

The original portal configuration script required the Supabase project URL in one exact format. A copied dashboard URL, project reference, path fragment or surrounding whitespace caused a false validation failure.

The repaired script accepts:

- `https://ojetmpchcwfpnjbuqvuv.supabase.co`
- `ojetmpchcwfpnjbuqvuv`
- `https://supabase.com/dashboard/project/ojetmpchcwfpnjbuqvuv`

It normalizes each accepted form to:

```text
https://ojetmpchcwfpnjbuqvuv.supabase.co
```

It also rejects `sb_secret_...` and service-role keys from browser configuration.
