[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow07-contract-snapshot.sql'
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required Workflow 07 contract snapshot was not found: $Path" }
Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 07 CONTRACT SNAPSHOT SQL: COPIED'
Write-Host 'Run it in Supabase SQL Editor. It is read-only and returns function, relation, column and index metadata.'
