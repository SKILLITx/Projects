[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'supabase\migrations\20260720000100_phase4_workflow04_results_publication.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Workflow 04 migration not found: $Path"
}

Get-Content -LiteralPath $Path -Raw | Set-Clipboard
Write-Host 'SIS 04 RESULTS MIGRATION SQL: COPIED'
Write-Host 'Paste it into Supabase SQL Editor and run it once.'
