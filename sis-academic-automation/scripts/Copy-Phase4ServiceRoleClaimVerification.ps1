[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\tests\phase4-service-role-claim-verification.sql'

if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
    throw "Missing verification SQL: $SqlPath"
}

Set-Clipboard -Value (Get-Content -LiteralPath $SqlPath -Raw)
Write-Host 'PHASE 4 SERVICE-ROLE CLAIM VERIFICATION SQL: COPIED'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it.'
