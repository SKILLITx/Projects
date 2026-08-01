[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\diagnostics\workflow04-publication-diagnostic.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Workflow 04 publication diagnostic SQL was not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 04 PUBLICATION DIAGNOSTIC SQL: COPIED'
Write-Host 'Run it in Supabase SQL Editor and return the single JSON result.'
Write-Host 'All diagnostic writes are rolled back.'
