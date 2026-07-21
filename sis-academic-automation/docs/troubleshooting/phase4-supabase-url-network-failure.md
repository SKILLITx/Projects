# Phase 4 — Supabase URL repair

The Workflow 01 canvas can show green nodes even when the business request
failed because the HTTP Request nodes use `neverError`. The actual result is
the queue outcome:

```text
Processing Status: failed
Error Code: NETWORK_FAILURE
```

The workflow URL comes from `SUPABASE_URL`, while the Supabase credential
supplies only the authorization headers during workflow execution. This
patch sets the environment value to the exact hosted project URL:

```text
https://ojetmpchcwfpnjbuqvuv.supabase.co
```

It then validates the URL, resolves its DNS host, confirms that HTTPS returns
a response, backs up `.env`, and restarts n8n while preserving ngrok.

No service-role key or other secret is included or printed.
