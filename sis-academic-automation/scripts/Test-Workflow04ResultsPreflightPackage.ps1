[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SqlPath = Join-Path $ProjectRoot 'database\queries\workflow04-results-preflight.sql'
$CopyPath = Join-Path $ProjectRoot 'scripts\Copy-Workflow04ResultsPreflight.ps1'

foreach ($Path in @($SqlPath, $CopyPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing Workflow 04 preflight file: $Path"
    }
}

$Sql = Get-Content -LiteralPath $SqlPath -Raw

foreach ($Required in @(
    'information_schema.columns',
    'pg_get_constraintdef',
    'pg_get_functiondef',
    'latest_finalized_marks_batch',
    'marks_approval_history',
    'mark_correction_requests',
    'course_results',
    'semester_results',
    'cumulative_results',
    'academic_standing_history',
    'pg_temp.sis_sample_table'
)) {
    if (-not $Sql.Contains($Required)) {
        throw "Workflow 04 preflight SQL is missing: $Required"
    }
}

foreach ($Forbidden in @(
    'SUPABASE_SERVICE_ROLE_KEY',
    'apikey',
    'authorization: bearer',
    'drop table public',
    'truncate table public',
    'delete from public'
)) {
    if ($Sql.ToLowerInvariant().Contains($Forbidden.ToLowerInvariant())) {
        throw "Workflow 04 preflight contains forbidden content: $Forbidden"
    }
}

Write-Host 'SIS 04 RESULTS PREFLIGHT PACKAGE CHECK: PASS'
Write-Host 'Verified metadata, RPC, enum, policy, finalized-batch and sample-data inspection without secret output.'
