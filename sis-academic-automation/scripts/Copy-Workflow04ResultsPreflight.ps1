[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\queries\workflow04-results-preflight.sql'

if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
    throw "Workflow 04 preflight SQL was not found: $SqlPath"
}

Get-Content -LiteralPath $SqlPath -Raw | Set-Clipboard

Write-Host 'WORKFLOW 04 RESULTS PREFLIGHT SQL: COPIED'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it.'
Write-Host 'Return the single workflow04_preflight JSON result.'
