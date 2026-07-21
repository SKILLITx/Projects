[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestScript = Join-Path $PSScriptRoot 'Test-Phase4ServiceRoleClaimPatch.ps1'
$SupabaseCli = Join-Path $ProjectRoot 'node_modules\.bin\supabase.cmd'

if (-not (Test-Path -LiteralPath $TestScript -PathType Leaf)) {
    throw "Missing patch test: $TestScript"
}

& $TestScript
if (-not $?) {
    throw 'Static patch verification failed.'
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

Write-Host 'PHASE 4 SERVICE-ROLE CLAIM DATABASE FIX: APPLIED'
Write-Host 'The database now recognizes service_role from the real PostgREST request.jwt.claims JSON.'
Write-Host 'No n8n credential change is required.'
