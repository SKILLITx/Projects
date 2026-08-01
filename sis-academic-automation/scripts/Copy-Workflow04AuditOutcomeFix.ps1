[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'supabase\migrations\20260720000200_phase4_workflow04_audit_outcome_fix.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Workflow 04 repair migration not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 04 AUDIT OUTCOME REPAIR SQL: COPIED'
Write-Host 'Paste it into Supabase SQL Editor and run it once.'
