[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MigrationPath = Join-Path $ProjectRoot 'supabase\migrations\20260720000200_phase4_workflow04_audit_outcome_fix.sql'

if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf)) {
    throw "Missing repair migration: $MigrationPath"
}

$Sql = Get-Content -LiteralPath $MigrationPath -Raw -Encoding UTF8

foreach ($Name in @(
    'rpc_decide_marks_batch',
    'rpc_request_mark_correction',
    'rpc_decide_mark_correction',
    'rpc_publish_results'
)) {
    if (-not $Sql.Contains("function public.$Name")) {
        throw "Repair migration is missing function: $Name"
    }
}

$AuditInsertCount = ([regex]::Matches(
    $Sql,
    'insert\s+into\s+audit\.audit_logs',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)).Count

$SuccessOutcomeCount = ([regex]::Matches(
    $Sql,
    "v_correlation_id,\s*'success',\s*jsonb_build_object",
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)).Count

if ($AuditInsertCount -ne 4) {
    throw "Expected 4 audit inserts; found $AuditInsertCount."
}
if ($SuccessOutcomeCount -ne 4) {
    throw "Expected 4 valid success outcomes; found $SuccessOutcomeCount."
}

if ($Sql -match "v_correlation_id,\s*'completed',\s*jsonb_build_object") {
    throw "Invalid audit outcome 'completed' remains in the repair migration."
}

Write-Host 'SIS 04 AUDIT OUTCOME FIX CHECK: PASS'
Write-Host 'Verified four Workflow 04 RPCs now write audit outcome success.'
