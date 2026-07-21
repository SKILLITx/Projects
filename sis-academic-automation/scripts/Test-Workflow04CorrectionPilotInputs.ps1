[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow04-correction-pilot-inputs.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing correction pilot query: $Path"
}

$Sql = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

foreach ($Required in @(
    'b3dd3f5d-ad13-498d-a7e4-41622bc8abbe',
    'student_mark_id',
    'student_number',
    'assessment_code',
    'current_marks',
    'proposed_corrected_marks',
    'maximum_marks',
    'current_calculation_version'
)) {
    if (-not $Sql.Contains($Required)) {
        throw "Correction pilot query is missing: $Required"
    }
}

foreach ($Forbidden in @(
    'insert into',
    'update public',
    'delete from',
    'truncate table',
    'drop table'
)) {
    if ($Sql.ToLowerInvariant().Contains($Forbidden)) {
        throw "Correction pilot query is not read-only: $Forbidden"
    }
}

Write-Host 'SIS 04 CORRECTION PILOT INPUT CHECK: PASS'
Write-Host 'Verified read-only selection of one safe approved pilot mark and complete form values.'
