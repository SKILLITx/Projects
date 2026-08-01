[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MigrationPath = Join-Path $ProjectRoot 'supabase\migrations\20260718000300_phase4_workflow03_pilot_teacher_assignment.sql'
$VerificationPath = Join-Path $ProjectRoot 'database\tests\phase4-workflow03-pilot-teacher-verification.sql'

foreach ($Path in @($MigrationPath, $VerificationPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
}

$Migration = Get-Content -LiteralPath $MigrationPath -Raw

foreach ($Fragment in @(
    'begin;',
    'commit;',
    'zaidrizwan.278@gmail.com',
    "i.code = 'DMU'",
    "c.code = 'ISB'",
    "co.offering_code = 'FALL-BA101-ISB'",
    "s.code = 'A'",
    "ra.role = 'teacher'",
    'insert into public.teacher_assignments',
    'if not exists'
)) {
    if (-not $Migration.Contains($Fragment)) {
        throw "Migration is missing required fragment: $Fragment"
    }
}

if ($Migration -match '(?im)^\s*(drop|truncate|delete)\s+') {
    throw 'Pilot teacher-assignment migration contains a destructive statement.'
}

if ($Migration -match '(?i)(service_role|anon_key|client_secret|refresh_token)\s*[:=]\s*[A-Za-z0-9._-]{12,}') {
    throw 'Possible secret detected in Workflow 03 pilot assignment package.'
}

Write-Host 'WORKFLOW 03 PILOT TEACHER ASSIGNMENT CHECK: PASS'
Write-Host 'Verified minimum DMU/ISB/BA101/A teacher scope, idempotent inserts and no destructive SQL.'
