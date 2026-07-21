[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow05-delivery-status.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Workflow 05 delivery-status query was not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 05 DELIVERY STATUS SQL: COPIED'
Write-Host 'Run it in Supabase SQL Editor and return the single JSON result.'
