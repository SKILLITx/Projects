# ngrok Setup

## Install

Install the ngrok Agent CLI for Windows, then verify it locally:

```powershell
ngrok help
```

## Connect the local agent to your account

Run the command shown in your ngrok dashboard on your own computer:

```powershell
ngrok config add-authtoken YOUR_TOKEN_FROM_NGROK_DASHBOARD
```

Do not place the token in `.env`, the repository, screenshots, chat or logs.

## Dynamic free URL

Leave `NGROK_DOMAIN=` blank in `.env`.

`Start-SIS.ps1` will:

1. start ngrok for local port 5678;
2. query the local ngrok API;
3. obtain the active HTTPS URL;
4. set `WEBHOOK_URL` and `N8N_PROXY_HOPS=1` only in the n8n child process;
5. verify the public route.

The script does not rewrite `.env` with a temporary URL.

## Optional fixed domain

Set only the domain value made available by the user's ngrok account:

```text
NGROK_DOMAIN=your-assigned-domain.ngrok.app
```

The script starts ngrok with its URL option. If the installed ngrok plan or CLI does not support that domain, ngrok exits and the error is written to `.runtime\logs\ngrok.stderr.log`.

## URL changes

When a dynamic URL changes:

- restart the full runtime with `Stop-SIS.ps1` and `Start-SIS.ps1`;
- update external services that store a complete webhook URL;
- update Google OAuth authorized redirect configuration when the redirect URL includes the temporary host;
- re-test with `Test-SIS.ps1`.

A dynamic ngrok URL is acceptable only for local testing and a controlled pilot with active operator support.
