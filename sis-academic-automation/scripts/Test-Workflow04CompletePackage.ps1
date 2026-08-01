[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\04-results-publication.json'
$MigrationPath = Join-Path $ProjectRoot 'supabase\migrations\20260720000100_phase4_workflow04_results_publication.sql'
$PortalAppPath = Join-Path $ProjectRoot 'portal\app.js'
$PortalIndexPath = Join-Path $ProjectRoot 'portal\index.html'

foreach ($Path in @($WorkflowPath, $MigrationPath, $PortalAppPath, $PortalIndexPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing Workflow 04 file: $Path"
    }
}

$WorkflowRaw = Get-Content -LiteralPath $WorkflowPath -Raw -Encoding UTF8
$Workflow = $WorkflowRaw | ConvertFrom-Json
$Nodes = @($Workflow.nodes)

$WorkflowName = [string]$Workflow.name
if (-not $WorkflowName.Contains('Results Approval and Publication')) {
    throw "Unexpected Workflow 04 name: $WorkflowName"
}

$RequiredNodeTypes = @(
    'n8n-nodes-base.webhook',
    'n8n-nodes-base.googleSheetsTrigger',
    'n8n-nodes-base.googleSheets',
    'n8n-nodes-base.httpRequest',
    'n8n-nodes-base.code',
    'n8n-nodes-base.if'
)
foreach ($Type in $RequiredNodeTypes) {
    if (-not ($Nodes.type -contains $Type)) {
        throw "Workflow 04 is missing node type: $Type"
    }
}

$WebhookPaths = @(
    $Nodes |
    Where-Object { $_.type -eq 'n8n-nodes-base.webhook' } |
    ForEach-Object { $_.parameters.path }
)
$ExpectedPaths = @(
    'staff/rpc_decide_marks_batch',
    'staff/rpc_decide_mark_correction',
    'staff/rpc_publish_results'
)
foreach ($Path in $ExpectedPaths) {
    if ($WebhookPaths -notcontains $Path) {
        throw "Workflow 04 is missing webhook path: $Path"
    }
}
if (($WebhookPaths | Sort-Object -Unique).Count -ne $WebhookPaths.Count) {
    throw 'Workflow 04 contains duplicate webhook paths.'
}

if ($Nodes.type -contains 'n8n-nodes-base.executeCommand') {
    throw 'Execute Command nodes are forbidden.'
}

foreach ($Required in @(
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'SIS_MARK_CORRECTION_RESPONSE_SHEET_ID',
    'SIS_MARK_CORRECTION_QUEUE_TAB_ID',
    'rpc_request_mark_correction_from_form',
    'AUTH_SESSION_INVALID',
    'identity_verified'
)) {
    if (-not $WorkflowRaw.Contains($Required)) {
        throw "Workflow 04 JSON is missing: $Required"
    }
}

foreach ($Forbidden in @(
    'service_role_key',
    'Bearer eyJ',
    'gemma-unfossilised-silverly',
    'ojetmpchcwfpnjbuqvuv'
)) {
    if ($WorkflowRaw.ToLowerInvariant().Contains($Forbidden.ToLowerInvariant())) {
        throw "Workflow 04 JSON contains forbidden deployment-specific content: $Forbidden"
    }
}

$Migration = Get-Content -LiteralPath $MigrationPath -Raw -Encoding UTF8
foreach ($Required in @(
    'app.results_staff_actor',
    'app.staff_can_administer_results',
    'app.staff_is_teacher_for_results_section',
    'app.calculate_course_result',
    'app.recalculate_academic_record',
    'public.rpc_decide_marks_batch',
    'public.rpc_request_mark_correction_from_form',
    'public.rpc_decide_mark_correction',
    'public.rpc_publish_results',
    'app.begin_idempotency',
    'ops.notification_outbox',
    'audit.audit_logs',
    'repeat_policy'
)) {
    if (-not $Migration.Contains($Required)) {
        throw "Workflow 04 migration is missing: $Required"
    }
}

foreach ($Forbidden in @(
    'SUPABASE_SERVICE_ROLE_KEY',
    'apikey:',
    'authorization: bearer',
    'drop table',
    'truncate table'
)) {
    if ($Migration.ToLowerInvariant().Contains($Forbidden.ToLowerInvariant())) {
        throw "Workflow 04 migration contains forbidden content: $Forbidden"
    }
}

$PortalApp = Get-Content -LiteralPath $PortalAppPath -Raw -Encoding UTF8
$PortalIndex = Get-Content -LiteralPath $PortalIndexPath -Raw -Encoding UTF8
if (-not $PortalApp.Contains('rpc_publish_results')) {
    throw 'The portal app is missing result publication support.'
}
if (-not $PortalIndex.Contains('publication-form')) {
    throw 'The portal HTML is missing the publication form.'
}

Write-Host 'SIS 04 COMPLETE PACKAGE CHECK: PASS'
Write-Host "Nodes: $($Nodes.Count)"
Write-Host "Webhook paths: $($WebhookPaths.Count)"
Write-Host 'Migration, authenticated webhook routing, correction queue, portal publication UI and acceptance evidence are present.'
