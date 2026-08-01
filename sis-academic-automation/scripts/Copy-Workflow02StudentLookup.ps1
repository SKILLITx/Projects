[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\queries\workflow02-student-number-lookup.sql'

if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
    throw "Missing student lookup SQL: $SqlPath"
}

Set-Clipboard -Value (Get-Content -LiteralPath $SqlPath -Raw)
Write-Host 'WORKFLOW 02 STUDENT LOOKUP SQL: COPIED'
Write-Host 'Paste it into the SIS Automation Supabase SQL Editor and run it.'
