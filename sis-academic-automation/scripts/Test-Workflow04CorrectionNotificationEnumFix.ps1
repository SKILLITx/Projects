[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'supabase\migrations\20260720000400_phase4_workflow04_correction_notification_enum_fix.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing Workflow 04 correction enum repair: $Path"
}

$Sql = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

foreach ($Required in @(
    'function public.rpc_request_mark_correction',
    "'email'::ops.notification_channel",
    "'marks.correction.requested'::text",
    "'success'",
    'ops.notification_outbox',
    'app.begin_idempotency',
    'app.complete_idempotency'
)) {
    if (-not $Sql.Contains($Required)) {
        throw "Workflow 04 correction enum repair is missing: $Required"
    }
}

if ($Sql -match "v_correlation_id,\s*'completed',\s*jsonb_build_object") {
    throw "Invalid audit outcome 'completed' remains."
}

Write-Host 'SIS 04 CORRECTION NOTIFICATION ENUM FIX CHECK: PASS'
Write-Host 'Verified explicit notification-channel enum casting and valid audit outcome.'
