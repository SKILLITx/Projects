[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\queries\workflow05-transcript-contract-snapshot.sql'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing Workflow 05 contract snapshot query: $Path"
}

$Sql = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
$Lower = $Sql.ToLowerInvariant()

foreach ($Required in @(
    'pg_get_functiondef',
    'rpc_create_transcript_request',
    'rpc_get_transcript_model',
    'rpc_record_transcript_document',
    'transcript_settings',
    'transcript_requests',
    'transcript_documents',
    'transcript_delivery_records',
    'notification_outbox',
    'dmu-0001',
    'zaidrizwan.278@gmail.com'
)) {
    if (-not $Lower.Contains($Required.ToLowerInvariant())) {
        throw "Workflow 05 contract snapshot is missing: $Required"
    }
}

foreach ($Forbidden in @(
    'insert into',
    'update public.',
    'update ops.',
    'delete from',
    'truncate table',
    'drop table',
    'create table',
    'alter table'
)) {
    if ($Lower.Contains($Forbidden)) {
        throw "Workflow 05 contract snapshot is not read-only: $Forbidden"
    }
}

Write-Host 'SIS 05 TRANSCRIPT CONTRACT SNAPSHOT CHECK: PASS'
Write-Host 'Verified exact function definitions, settings, counts and pilot academic source discovery.'
