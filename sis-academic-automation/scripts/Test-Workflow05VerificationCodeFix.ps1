[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\migrations\20260720000600_phase4_workflow05_verification_code_generation_fix.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing Workflow 05 repair migration: $Path"
}

$Sql = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
$Lower = $Sql.ToLowerInvariant()

foreach ($Required in @(
    'create or replace function public.rpc_create_transcript_request',
    "replace(gen_random_uuid()::text, '-', '')",
    "set search_path to ''",
    'commit;'
)) {
    if (-not $Lower.Contains($Required.ToLowerInvariant())) {
        throw "Workflow 05 repair is missing: $Required"
    }
}

# Strip SQL line comments before checking executable SQL. The migration's
# explanatory comments intentionally mention the old gen_random_bytes() call.
$ExecutableLines = foreach ($Line in ($Sql -split "`r?`n")) {
    $Trimmed = $Line.TrimStart()
    if (-not $Trimmed.StartsWith('--')) { $Line }
}
$ExecutableSql = ($ExecutableLines -join "`n").ToLowerInvariant()

if ($ExecutableSql.Contains('gen_random_bytes(')) {
    throw 'The obsolete executable gen_random_bytes() call is still present.'
}

Write-Host 'SIS 05 VERIFICATION CODE GENERATION FIX CHECK: PASS'
Write-Host 'Verified UUID-based verification-code generation; explanatory SQL comments were ignored.'
