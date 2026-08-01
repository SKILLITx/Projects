[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\tests\workflow07-hosted-verification.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required file was not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 07 HOSTED VERIFICATION SQL: COPIED'
Write-Host 'Run it in Supabase SQL Editor.'
