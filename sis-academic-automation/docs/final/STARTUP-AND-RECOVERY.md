# Startup and Recovery Guide

## Start the complete pilot

Run in Windows PowerShell 5.1:

```powershell
$repo="D:\AI automation\zaid278-workflows\skill it\Project 1\V2\sis-academic-automation"; if (-not (Test-Path -LiteralPath $repo)) { throw "Repository not found: $repo" }; Set-Location -LiteralPath $repo; npm run sis:start
```

The unified launcher verifies n8n at `http://127.0.0.1:5678/`, the staff portal at `http://127.0.0.1:4173/`, and the transcript portal at `http://127.0.0.1:4173/transcript-pilot.html`.

Do not run `n8n start` from `C:\Users\DeLL`; that starts the older default n8n user folder rather than this repository's isolated runtime.

The project database is stored under `.runtime\n8n-user\.n8n\database.sqlite`.

## Stop the pilot

```powershell
$repo="D:\AI automation\zaid278-workflows\skill it\Project 1\V2\sis-academic-automation"; if (-not (Test-Path -LiteralPath $repo)) { throw "Repository not found: $repo" }; Set-Location -LiteralPath $repo; & ".\scripts\Stop-SIS.ps1"
```

## Private backup and restore

The verified private backup contains secrets, local configuration, and the n8n SQLite database. It must never be uploaded or shared.

Restore only into an isolated folder first. Verify `BACKUP-MANIFEST.json`, confirm the SQLite database exists, export workflows from the restored copy, and validate the stabilized workflow names before replacing any working environment.

## Dynamic ngrok warning

A changed ngrok URL may require updating webhook targets, OAuth redirect configuration, external registrations, and portal configuration. Never print credentials while troubleshooting.
