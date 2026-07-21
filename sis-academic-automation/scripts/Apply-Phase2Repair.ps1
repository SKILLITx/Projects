[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$NpxCommand = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
if (-not $NpxCommand) {
    $NpxCommand = Get-Command 'npx' -ErrorAction Stop
}

Push-Location -LiteralPath $ProjectRoot
try {
    & (Join-Path $PSScriptRoot 'Test-Phase2Package.ps1')
    if (-not $?) {
        throw 'Phase 2 static verification failed. The database push was not started.'
    }

    Write-Host ''
    Write-Host 'Applying the remaining Phase 2 migrations...'
    & $NpxCommand.Source supabase db push
    if ($LASTEXITCODE -ne 0) {
        throw "Supabase database push failed with exit code $LASTEXITCODE."
    }

    Write-Host ''
    Write-Host 'Verifying local and remote migration history...'
    & $NpxCommand.Source supabase migration list
    if ($LASTEXITCODE -ne 0) {
        throw "Supabase migration history verification failed with exit code $LASTEXITCODE."
    }

    & (Join-Path $PSScriptRoot 'Copy-Phase2Verification.ps1')
    if (-not $?) {
        throw 'The hosted Phase 2 verification SQL could not be copied.'
    }

    Write-Host ''
    Write-Host 'PHASE 2 REPAIR/APPLY STEP: PASS'
    Write-Host 'Paste the copied SQL into the Supabase SQL Editor and run it once.'
}
finally {
    Pop-Location
}
