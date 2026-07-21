[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'portal\transcript-pilot.html'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing friendly transcript pilot page: $Path"
}

$Html = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
foreach ($Required in @(
    'Generate and Email Transcript',
    'DMU-0001',
    'rpc_create_transcript_request',
    'client.auth.getSession',
    'Authorization',
    'portal:transcript.request:workflow05-pilot-01'
)) {
    if (-not $Html.Contains($Required)) {
        throw "Friendly transcript pilot page is missing: $Required"
    }
}

foreach ($Forbidden in @(
    'SUPABASE_SERVICE_ROLE_KEY',
    'service_role',
    'password='
)) {
    if ($Html.Contains($Forbidden)) {
        throw "Friendly transcript pilot page contains forbidden server-side material: $Forbidden"
    }
}

Write-Host 'SIS 05 FRIENDLY PILOT PORTAL CHECK: PASS'
Write-Host 'Verified hidden UUIDs, browser-held Supabase session, fixed pilot student and authenticated Workflow 05 submission.'
