[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'tests\acceptance\workflow05-durable-outcomes.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required Workflow 05 file was not found: $Path"
}

Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | Set-Clipboard
Write-Host 'SIS 05 DURABLE OUTCOMES SQL: COPIED'
Write-Host 'Run it after the positive end-to-end transcript test.'
