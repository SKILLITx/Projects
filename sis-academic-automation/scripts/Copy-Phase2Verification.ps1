[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\tests\phase2-hosted-verification.sql'
if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) { throw "Missing verification SQL: $SqlPath" }
Set-Clipboard -Value (Get-Content -LiteralPath $SqlPath -Raw)
Write-Host 'Phase 2 hosted verification SQL copied to the clipboard.'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it once.'
