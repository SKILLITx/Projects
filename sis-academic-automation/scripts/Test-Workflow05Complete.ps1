[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestPath = Join-Path $ProjectRoot 'tests\static\validate-workflow05-complete.js'

if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) {
    throw "Workflow 05 static test was not found: $TestPath"
}

& node $TestPath
if ($LASTEXITCODE -ne 0) {
    throw "Workflow 05 static validation failed with exit code $LASTEXITCODE."
}
