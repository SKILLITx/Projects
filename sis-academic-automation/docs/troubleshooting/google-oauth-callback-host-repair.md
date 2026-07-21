# Google OAuth callback host repair

## Problem

The n8n editor session was active on the ngrok hostname while the OAuth
callback returned to `localhost`. Browser sessions are hostname-scoped, so
the callback could not use the ngrok login session and returned
`Unauthorized`.

The user also could not sign in at `localhost`, so resetting n8n user
management was deliberately avoided.

## Repair

This patch adds an optional `EditorBaseUrl` argument to `Start-N8n.ps1`.
The repair launcher:

1. reads the currently running HTTPS ngrok tunnel;
2. preserves the ngrok process and public hostname;
3. restarts only n8n;
4. sets both `WEBHOOK_URL` and `N8N_EDITOR_BASE_URL` to the same ngrok URL;
5. leaves `.env` unchanged.

The Google OAuth callback therefore returns to the same hostname as the
existing n8n browser session.

## Security

- No password is requested.
- No OAuth client secret is requested.
- No service-role key is requested.
- The normal local-runtime startup remains available.
- The original `Start-N8n.ps1` is backed up before patching.
