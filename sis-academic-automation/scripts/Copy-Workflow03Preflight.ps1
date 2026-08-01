[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\queries\workflow03-preflight.sql'

if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
    throw "Missing Workflow 03 preflight SQL: $SqlPath"
}

Set-Clipboard -Value (Get-Content -LiteralPath $SqlPath -Raw)

Write-Host 'WORKFLOW 03 PREFLIGHT SQL: COPIED'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it.'
