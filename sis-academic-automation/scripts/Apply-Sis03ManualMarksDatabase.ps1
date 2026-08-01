[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestScript = Join-Path $PSScriptRoot 'Test-Sis03ManualMarksPackage.ps1'
$SupabaseCli = Join-Path $ProjectRoot 'node_modules\.bin\supabase.cmd'

& $TestScript
if (-not $?) {
    throw 'Workflow 03 package verification failed.'
}

if (-not (Test-Path -LiteralPath $SupabaseCli -PathType Leaf)) {
    throw "Local Supabase CLI was not found: $SupabaseCli"
}

Push-Location $ProjectRoot
try {
    & $SupabaseCli db push --yes
    if ($LASTEXITCODE -ne 0) {
        throw "Supabase db push failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

Write-Host 'SIS 03 MANUAL MARKS DATABASE SUPPORT: APPLIED'
Write-Host 'The service-role-only marks form RPC is available for workflow configuration.'
