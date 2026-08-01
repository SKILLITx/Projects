[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow04-correction-decision-inputs.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing correction-decision query: $Path"
}

$Sql = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

foreach ($Required in @(
    '1dcc2a39-ed5f-456c-a5d0-418d6b5ed5b9',
    'correction_request_id',
    'correction_status',
    'current_stored_marks',
    'proposed_marks',
    'current_calculation_version',
    'course_offering_id'
)) {
    if (-not $Sql.Contains($Required)) {
        throw "Correction-decision query is missing: $Required"
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
        throw "Correction-decision query is not read-only: $Forbidden"
    }
}

Write-Host 'SIS 04 CORRECTION DECISION INPUT CHECK: PASS'
Write-Host 'Verified read-only resolution of the completed pilot correction request.'
