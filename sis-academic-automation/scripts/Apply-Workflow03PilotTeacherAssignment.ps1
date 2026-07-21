[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestScript = Join-Path $PSScriptRoot 'Test-Workflow03PilotTeacherAssignment.ps1'
$SupabaseCli = Join-Path $ProjectRoot 'node_modules\.bin\supabase.cmd'

& $TestScript
if (-not $?) {
    throw 'Workflow 03 pilot teacher-assignment static verification failed.'
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

Write-Host 'WORKFLOW 03 PILOT TEACHER ASSIGNMENT: APPLIED'
Write-Host 'The current pilot account is assigned only to DMU / ISB / FALL-BA101-ISB / Section A.'
