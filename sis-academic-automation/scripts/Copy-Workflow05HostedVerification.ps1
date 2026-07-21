[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow05-hosted-verification.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required Workflow 05 file was not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 05 HOSTED VERIFICATION SQL: COPIED'
Write-Host 'Run it after the migration and return the single JSON result.'
