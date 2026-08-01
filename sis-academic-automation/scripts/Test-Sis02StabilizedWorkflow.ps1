[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\02-enrollment-lifecycle-stabilized.json'

if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    throw "Missing stabilized Workflow 02: $WorkflowPath"
}

$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$Nodes = @($Workflow.nodes)

function Get-Node([string]$Name) {
    $Matches = @($Nodes | Where-Object { $_.name -eq $Name })
    if ($Matches.Count -ne 1) {
        throw "Expected exactly one node named '$Name'."
    }
    return $Matches[0]
}

if ($Workflow.active -ne $false) {
    throw 'Workflow 02 must import inactive.'
}

$WorkflowIdProperty = $Workflow.PSObject.Properties['id']
if ($null -ne $WorkflowIdProperty -and -not [string]::IsNullOrWhiteSpace([string]$WorkflowIdProperty.Value)) {
    throw 'Workflow 02 must import as a new workflow and not overwrite the original.'
}

$Trigger = Get-Node 'Google Sheets Queue Trigger'
$Range = $Trigger.parameters.options.dataLocationOnSheet.values.range
if ($Range -ne 'A1:P') {
    throw "The enrollment trigger range must be A1:P, found '$Range'."
}

$Normalize = Get-Node 'Normalize Enrollment Queue Row'
foreach ($Fragment in @(
    "status === 'pending'",
    'VALIDATION_DUPLICATE_COURSE_CODE',
    'VALIDATION_SECTION_ALIGNMENT',
    'return { json:'
)) {
    if (-not $Normalize.parameters.jsCode.Contains($Fragment)) {
        throw "Enrollment normalizer is missing: $Fragment"
    }
}

$Outcome = Get-Node 'Build Enrollment Queue Outcome'
foreach ($Fragment in @(
    '$(''Normalize Enrollment Queue Row'').item.json',
    'bodyError.code',
    'NETWORK_FAILURE',
    'httpStatusCode',
    'return {'
)) {
    if (-not $Outcome.parameters.jsCode.Contains($Fragment)) {
        throw "Enrollment outcome parser is missing: $Fragment"
    }
}

$Update = Get-Node 'Update Automation Queue'
if ($Update.retryOnFail -ne $true -or $Update.maxTries -ne 3) {
    throw 'The enrollment queue update must retry three times.'
}

$IfConnections = $Workflow.connections.'Is Queue Row Processable?'.main
if ($IfConnections.Count -lt 2 -or $IfConnections[1].Count -lt 1 -or $IfConnections[1][0].node -ne 'Skip Non-Pending Queue Row') {
    throw 'The false branch must have an explicit terminal.'
}

$OutcomeConnections = $Workflow.connections.'Build Enrollment Queue Outcome'.main[0]
if ($OutcomeConnections.Count -ne 1 -or $OutcomeConnections[0].node -ne 'Update Automation Queue') {
    throw 'Workflow 02 must update the queue before completion logging.'
}

$UpdateConnections = $Workflow.connections.'Update Automation Queue'.main[0]
if ($UpdateConnections.Count -ne 1 -or $UpdateConnections[0].node -ne 'Log Workflow Completion') {
    throw 'Workflow 02 completion logging must follow the queue update.'
}

$StartBody = (Get-Node 'Log Workflow Start').parameters.jsonBody
$CompleteBody = (Get-Node 'Log Workflow Completion').parameters.jsonBody

if (-not $StartBody.Contains(':workflow-start')) {
    throw 'The enrollment start-log idempotency suffix is missing.'
}

if (-not $CompleteBody.Contains(':workflow-completion')) {
    throw 'The enrollment completion-log idempotency suffix is missing.'
}

foreach ($Name in @('Log Workflow Start', 'Submit Business RPC', 'Log Workflow Completion')) {
    $Node = Get-Node $Name
    if ($Node.parameters.options.timeout -ne 15000) {
        throw "$Name must have a 15-second timeout."
    }
}

if (
    $Workflow.settings.saveDataSuccessExecution -ne 'all' -or
    $Workflow.settings.saveDataErrorExecution -ne 'all' -or
    $Workflow.settings.saveManualExecutions -ne $true
) {
    throw 'Workflow 02 pilot execution evidence settings are incomplete.'
}

Write-Host 'SIS 02 STABILIZED WORKFLOW CHECK: PASS'
Write-Host 'Verified atomic queue assumptions, strict pending routing, Code-node contracts, item-aware mapping, error parsing, retries and deterministic completion order.'
