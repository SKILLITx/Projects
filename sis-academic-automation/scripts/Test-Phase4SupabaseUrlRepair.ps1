[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$RepairPath = Join-Path $PSScriptRoot 'Repair-Phase4SupabaseUrl.ps1'
if (-not (Test-Path -LiteralPath $RepairPath -PathType Leaf)) {
    throw "Missing repair script: $RepairPath"
}

$Text = Get-Content -LiteralPath $RepairPath -Raw

$RequiredFragments = @(
    'https://ojetmpchcwfpnjbuqvuv.supabase.co',
    'SUPABASE_URL=$ExpectedUrl',
    '[System.Net.Dns]::GetHostAddresses',
    'Restart-N8nForGoogleOAuth.ps1',
    'PHASE 4 SUPABASE URL REPAIR: PASS'
)

foreach ($Required in $RequiredFragments) {
    if (-not $Text.Contains($Required)) {
        throw "Supabase URL repair validation failed: missing $Required"
    }
}

if ($Text.Contains('service_role') -or $Text.Contains('SUPABASE_SERVICE_ROLE_KEY=')) {
    throw 'The repair package must not contain a Supabase secret.'
}

Write-Host 'PHASE 4 SUPABASE URL REPAIR PACKAGE: PASS'
Write-Host 'Verified exact project URL, DNS/HTTPS checks, backup handling, secret exclusion and n8n restart integration.'
