[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\migrations\20260720000500_phase4_workflow05_transcript_delivery.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required Workflow 05 file was not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 05 COMPLETE MIGRATION SQL: COPIED'
Write-Host 'Run it once in Supabase SQL Editor.'
