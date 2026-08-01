[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\migrations\20260721000200_phase4_workflow07_admin_search_dashboard_complete.sql'
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required Workflow 07 migration was not found: $Path" }
Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 07 COMPLETE MIGRATION SQL: COPIED'
Write-Host 'Run it once in Supabase SQL Editor after reviewing the contract snapshot.'
