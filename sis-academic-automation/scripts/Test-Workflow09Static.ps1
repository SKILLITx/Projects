[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestPath = Join-Path $ProjectRoot 'tests\static\workflow09-operations-monitoring.test.mjs'
if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) {
    throw "Workflow 09 static test was not found: $TestPath"
}
& node $TestPath
if ($LASTEXITCODE -ne 0) {
    throw "Workflow 09 static validation failed with exit code $LASTEXITCODE."
}
Write-Host 'SIS 09 STATIC VALIDATION: PASS'
