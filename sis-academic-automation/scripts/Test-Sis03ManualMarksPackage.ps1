[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\03-marks-intake-stabilized.json'
$MigrationPath = Join-Path $ProjectRoot 'supabase\migrations\20260718000400_phase4_workflow03_marks_form_integration.sql'

foreach ($Path in @($WorkflowPath, $MigrationPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
}

$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$Nodes = @($Workflow.nodes)
$Migration = Get-Content -LiteralPath $MigrationPath -Raw

function Get-Node([string]$Name) {
    $Matches = @($Nodes | Where-Object { $_.name -eq $Name })
    if ($Matches.Count -ne 1) {
        throw "Expected exactly one node named '$Name'."
    }
    return $Matches[0]
}

if ($Workflow.active -ne $false) {
    throw 'Workflow 03 must import inactive.'
}

$IdProperty = $Workflow.PSObject.Properties['id']
if ($null -ne $IdProperty -and -not [string]::IsNullOrWhiteSpace([string]$IdProperty.Value)) {
    throw 'Workflow 03 must import separately and not overwrite another workflow.'
}

$Normalize = Get-Node 'Normalize Marks Queue Row'
if ($Normalize.parameters.mode -ne 'runOnceForEachItem') {
    throw 'Marks normalizer must run once for each queue item.'
}

foreach ($Fragment in @(
    "status === 'pending'",
    "operation === 'marks.batch.submit'",
    'VALIDATION_DUPLICATE_STUDENT_NUMBER',
    'AUTH_CAPTURED_TEACHER_EMAIL_REQUIRED',
    'submission_state: submissionState',
    'is_absent: isAbsent',
    'is_missing: isMissing'
)) {
    if (-not ([string]$Normalize.parameters.jsCode).Contains($Fragment)) {
        throw "Marks normalizer is missing: $Fragment"
    }
}

$Trigger = Get-Node 'Google Sheets Queue Trigger'
if ($Trigger.parameters.options.dataLocationOnSheet.values.range -ne 'A1:P') {
    throw 'Workflow 03 trigger must read A1:P.'
}

foreach ($Name in @(
    'Log Workflow Start',
    'Submit Marks Form RPC',
    'Log Workflow Completion'
)) {
    $Node = Get-Node $Name
    if ($Node.parameters.options.timeout -ne 15000) {
        throw "$Name must have a 15-second timeout."
    }
    if ($Node.retryOnFail -ne $true -or $Node.maxTries -ne 3) {
        throw "$Name must use three bounded retries."
    }
}

$Outcome = Get-Node 'Build Marks Queue Outcome'
if ($Outcome.parameters.mode -ne 'runOnceForEachItem') {
    throw 'Marks outcome builder must run once per item.'
}
if ([string]$Outcome.parameters.jsCode -match 'return\s*\[\s*\{\s*json\s*:') {
    throw 'Marks outcome builder returns an invalid per-item array.'
}

$QueueConnections = $Workflow.connections.'Build Marks Queue Outcome'.main[0]
if ($QueueConnections.Count -ne 1 -or $QueueConnections[0].node -ne 'Update Automation Queue') {
    throw 'Marks queue outcome must be written before completion logging.'
}

$LogConnections = $Workflow.connections.'Update Automation Queue'.main[0]
if ($LogConnections.Count -ne 1 -or $LogConnections[0].node -ne 'Log Workflow Completion') {
    throw 'Workflow completion logging must follow the queue update.'
}

foreach ($Fragment in @(
    'create or replace function public.rpc_submit_marks_from_form',
    'perform app.require_service()',
    'AUTH_TEACHER_ASSIGNMENT_REQUIRED',
    'MARKS_STUDENT_MISSING_FROM_SUBMISSION',
    'public.rpc_submit_marks_batch',
    'public.rpc_finalize_marks_batch',
    'marks.submission.confirmed',
    'on conflict',
    'grant execute on function public.rpc_submit_marks_from_form(jsonb)',
    'to service_role'
)) {
    if (-not $Migration.Contains($Fragment)) {
        throw "Workflow 03 migration is missing: $Fragment"
    }
}

if ($Migration -match '(?im)^\s*(drop|truncate|delete)\s+') {
    throw 'Workflow 03 migration contains a destructive statement.'
}

$Combined = (Get-Content -LiteralPath $WorkflowPath -Raw) + "`n" + $Migration
if ($Combined -match '(?i)(service_role|anon_key|client_secret|refresh_token)\s*[:=]\s*[A-Za-z0-9._-]{12,}') {
    throw 'Possible secret detected in Workflow 03 package.'
}

if (
    $Workflow.settings.saveDataSuccessExecution -ne 'all' -or
    $Workflow.settings.saveDataErrorExecution -ne 'all' -or
    $Workflow.settings.saveManualExecutions -ne $true
) {
    throw 'Workflow 03 execution evidence settings are incomplete.'
}

Write-Host 'SIS 03 MANUAL MARKS PACKAGE CHECK: PASS'
Write-Host 'Verified teacher-email enforcement, marks parsing, class coverage validation, finalization, queue ordering, retries and service-role-only RPC access.'
