[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$NodeTest = Join-Path $PSScriptRoot 'test-phase4-wave1-code-contracts.js'

if (-not (Test-Path -LiteralPath $NodeTest -PathType Leaf)) {
    throw "Missing Code-contract test: $NodeTest"
}

& node $NodeTest
if ($LASTEXITCODE -ne 0) {
    throw "Phase 4 Wave 1 Code-contract test failed with exit code $LASTEXITCODE."
}

$Required = @(
    'workflows\01-student-intake.json',
    'workflows\02-enrollment-lifecycle.json',
    'workflows\08-notification-dispatcher.json',
    'scripts\Repair-LivePhase4Wave1CodeContracts.ps1'
)

foreach ($RelativePath in $Required) {
    $Path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing repaired Wave 1 file: $RelativePath"
    }
}

Write-Host 'PHASE 4 WAVE 1 CODE CONTRACT REPAIR PACKAGE: PASS'
Write-Host 'The repaired source workflows and live credential-preserving repair script are present.'
