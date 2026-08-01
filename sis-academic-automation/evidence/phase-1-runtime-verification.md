# Phase 1 Runtime Verification

Verified at: 2026-07-16T18:00:02+00:00

## Environment

- Windows PowerShell: 5.1.26100.8875
- Node.js: 24.12.0
- npm: 11.6.2
- n8n: 2.4.0
- ngrok: 3.39.8-msix-stable
- local n8n port: 5678

## Passed checks

1. Environment initialization completed without exposing the generated encryption key.
2. Project-local dependencies installed.
3. Environment validator passed.
4. Repaired static validator passed.
5. n8n and ngrok started together.
6. Local health endpoint returned HTTP 200.
7. Public ngrok health endpoint returned HTTP 200.
8. Controlled shutdown succeeded.
9. Clean restart succeeded.
10. Final local and public health validation passed.

## Verified endpoints

- Local editor/health base: `http://127.0.0.1:5678/`
- Public URL observed during verification: `https://gemma-unfossilised-silverly.ngrok-free.dev/`

The public URL is dynamic and must not be treated as permanent configuration.

## Result

Phase 1 is complete.

Phase 2 may begin after a completely new Supabase project is created.
