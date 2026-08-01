[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\tests\phase4-workflow03-pilot-teacher-verification.sql'

if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
    throw "Missing verification SQL: $SqlPath"
}

Set-Clipboard -Value (Get-Content -LiteralPath $SqlPath -Raw)

Write-Host 'WORKFLOW 03 PILOT TEACHER VERIFICATION SQL: COPIED'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it.'
