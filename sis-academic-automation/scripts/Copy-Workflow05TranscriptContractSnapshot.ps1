[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow05-transcript-contract-snapshot.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Workflow 05 contract snapshot SQL was not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 05 TRANSCRIPT CONTRACT SNAPSHOT SQL: COPIED'
Write-Host 'Run it in Supabase SQL Editor and return the single JSON result.'
