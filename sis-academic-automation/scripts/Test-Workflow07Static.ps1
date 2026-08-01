[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestPath = Join-Path $ProjectRoot 'tests\static\workflow07-admin-dashboard.test.mjs'

if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) {
    throw "Workflow 07 static test was not found: $TestPath"
}

& node $TestPath
if ($LASTEXITCODE -ne 0) {
    throw "Workflow 07 static validation failed with exit code $LASTEXITCODE."
}

Write-Host 'SIS 07 STATIC VALIDATION: PASS'
