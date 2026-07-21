# Local Runtime Setup — Windows 11

## Scope

This setup creates a controlled local pilot runtime. It does not create a hosted production deployment.

## Prerequisites

- Windows 11
- Windows PowerShell 5.1
- Node.js between 20.19 and 24.x
- npm
- ngrok Agent CLI
- an ngrok account for an auth token

The project installs n8n locally through npm and pins it to version `2.4.0`.

## Initial setup

Run each command from the repository root.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Initialize-Environment.ps1"
```

Expected result:

- `.env` is created;
- an encryption key is generated locally and is not printed;
- `.runtime\logs`, `.runtime\pids` and `.runtime\n8n-user` are created.

Install the pinned npm dependency:

```powershell
npm install
```

Expected result:

- `node_modules` is created;
- `node_modules\.bin\n8n.cmd` exists;
- `npx n8n --version` or the local command reports `2.4.0`.

Validate the environment:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Environment.ps1"
```

Expected result: every required line reports `PASS` and the final message is `Environment validation passed.`

## Start and stop

Start n8n and ngrok together:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-SIS.ps1"
```

Expected result:

- n8n starts on `http://localhost:5678/`;
- ngrok supplies an HTTPS public URL;
- the public URL reaches n8n;
- PIDs and logs are stored under `.runtime`;
- the current public URL is stored in `.runtime\active-webhook-url.txt`.

Test both endpoints:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-SIS.ps1"
```

Stop both processes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Stop-SIS.ps1"
```

## Runtime files

- `.runtime\n8n-user` — n8n user folder and SQLite metadata location
- `.runtime\logs\n8n.stdout.log`
- `.runtime\logs\n8n.stderr.log`
- `.runtime\logs\ngrok.stdout.log`
- `.runtime\logs\ngrok.stderr.log`
- `.runtime\pids\n8n.pid`
- `.runtime\pids\ngrok.pid`
- `.runtime\active-webhook-url.txt`

These files are excluded from Git.
