[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\queries\workflow03-marks-status.sql'

if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
    throw "Missing Workflow 03 status SQL: $SqlPath"
}

Set-Clipboard -Value (Get-Content -LiteralPath $SqlPath -Raw)

Write-Host 'WORKFLOW 03 MARKS STATUS SQL: COPIED'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it.'
