[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow05-preflight.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing Workflow 05 preflight query: $Path"
}

$Sql = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
$Lower = $Sql.ToLowerInvariant()

foreach ($Required in @(
    'transcript_requests',
    'transcript_documents',
    'transcript_delivery_records',
    'student_program_registrations',
    'course_results',
    'semester_results',
    'cumulative_results',
    'transcript_functions',
    'pilot_student',
    'dmu-0001',
    'zaidrizwan.278@gmail.com'
)) {
    if (-not $Lower.Contains($Required.ToLowerInvariant())) {
        throw "Workflow 05 preflight is missing: $Required"
    }
}

foreach ($Forbidden in @(
    'insert into',
    'update public.',
    'delete from',
    'truncate table',
    'drop table',
    'create table',
    'alter table'
)) {
    if ($Lower.Contains($Forbidden)) {
        throw "Workflow 05 preflight is not read-only: $Forbidden"
    }
}

Write-Host 'SIS 05 TRANSCRIPT PREFLIGHT CHECK: PASS'
Write-Host 'Verified read-only schema, RPC, staff and published-student discovery.'
