[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow09-verification.sql'
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required Workflow 09 file was not found: $Path" }
Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 09 VERIFICATION SQL: COPIED'
Write-Host 'Run it in Supabase SQL Editor after the migration. Every compact check must report PASS.'
