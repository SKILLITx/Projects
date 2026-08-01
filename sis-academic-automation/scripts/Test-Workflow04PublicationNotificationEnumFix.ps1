[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MigrationPath = Join-Path $ProjectRoot 'supabase\migrations\20260720000300_phase4_workflow04_publication_notification_enum_fix.sql'

if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf)) {
    throw "Missing Workflow 04 publication enum repair: $MigrationPath"
}

$Sql = Get-Content -LiteralPath $MigrationPath -Raw -Encoding UTF8

foreach ($Required in @(
    'function public.rpc_publish_results',
    "'email'::ops.notification_channel",
    "'results.published'::text",
    "'success'",
    'app.begin_idempotency',
    'app.recalculate_academic_record',
    'ops.notification_outbox'
)) {
    if (-not $Sql.Contains($Required)) {
        throw "Workflow 04 publication enum repair is missing: $Required"
    }
}

if ($Sql -match "v_correlation_id,\s*'completed',\s*jsonb_build_object") {
    throw "Invalid audit outcome 'completed' remains."
}

Write-Host 'SIS 04 PUBLICATION NOTIFICATION ENUM FIX CHECK: PASS'
Write-Host 'Verified explicit notification-channel enum casting and valid audit outcome.'
