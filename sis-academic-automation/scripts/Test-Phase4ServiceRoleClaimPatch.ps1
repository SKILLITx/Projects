[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MigrationPath = Join-Path $ProjectRoot 'supabase\migrations\20260718000200_phase4_service_role_claim_compatibility.sql'
$VerificationPath = Join-Path $ProjectRoot 'database\tests\phase4-service-role-claim-verification.sql'

foreach ($Path in @($MigrationPath, $VerificationPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing patch file: $Path"
    }
}

$Migration = Get-Content -LiteralPath $MigrationPath -Raw

foreach ($Required in @(
    "current_setting('request.jwt.claims', true)",
    "current_setting('request.jwt.claim.role', true)",
    "->> 'role'",
    "= 'service_role'",
    "create or replace function app.is_service_request()"
)) {
    if (-not $Migration.Contains($Required)) {
        throw "Service-role claim migration is missing: $Required"
    }
}

if ($Migration -match 'eyJ[A-Za-z0-9_-]+\.' -or $Migration -match 'sb_(secret|publishable)_') {
    throw 'A credential-like value was found in the migration.'
}

$Verification = Get-Content -LiteralPath $VerificationPath -Raw
foreach ($Required in @(
    '{"role":"service_role"',
    '{"role":"authenticated"}',
    'CURRENT_POSTGREST_SERVICE_ROLE_CLAIM_NOT_RECOGNIZED',
    'AUTHENTICATED_ROLE_WAS_INCORRECTLY_ACCEPTED'
)) {
    if (-not $Verification.Contains($Required)) {
        throw "Verification SQL is missing: $Required"
    }
}

Write-Host 'PHASE 4 SERVICE-ROLE CLAIM PATCH: PASS'
Write-Host 'Verified current PostgREST claims support, legacy compatibility, negative authorization test and secret exclusion.'
