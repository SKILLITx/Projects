[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\01-student-intake-stabilized.json'

if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    throw "Missing stabilized workflow: $WorkflowPath"
}

$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$Nodes = @($Workflow.nodes)

function Get-Node([string]$Name) {
    $Match = @($Nodes | Where-Object { $_.name -eq $Name })
    if ($Match.Count -ne 1) {
        throw "Expected exactly one node named '$Name'."
    }
    return $Match[0]
}

if ($Workflow.active -ne $false) {
    throw 'The stabilized workflow must import inactive.'
}

if ($null -ne $Workflow.id) {
    throw 'The stabilized workflow must not overwrite the existing workflow ID.'
}

$Normalize = Get-Node 'Normalize Student Queue Row'
if (-not $Normalize.parameters.jsCode.Contains("status === 'pending'")) {
    throw 'Strict pending-row validation is missing.'
}

$Outcome = Get-Node 'Build Student Queue Outcome'
foreach ($Fragment in @(
    '$(''Normalize Student Queue Row'').item.json',
    'bodyError.code',
    'NETWORK_FAILURE',
    'httpStatusCode'
)) {
    if (-not $Outcome.parameters.jsCode.Contains($Fragment)) {
        throw "Outcome parser is missing: $Fragment"
    }
}

$Skip = Get-Node 'Skip Non-Pending Queue Row'
$Update = Get-Node 'Update Automation Queue'

if ($Update.retryOnFail -ne $true -or $Update.maxTries -ne 3) {
    throw 'The critical queue update retry policy is missing.'
}

$IfConnections = $Workflow.connections.'Is Queue Row Processable?'.main
if ($IfConnections.Count -lt 2 -or $IfConnections[1][0].node -ne 'Skip Non-Pending Queue Row') {
    throw 'The IF false branch is not connected to the explicit terminal.'
}

$BuildConnections = $Workflow.connections.'Build Student Queue Outcome'.main[0]
if ($BuildConnections.Count -ne 1 -or $BuildConnections[0].node -ne 'Update Automation Queue') {
    throw 'The completion sequence must update the queue first.'
}

$UpdateConnections = $Workflow.connections.'Update Automation Queue'.main[0]
if ($UpdateConnections.Count -ne 1 -or $UpdateConnections[0].node -ne 'Log Workflow Completion') {
    throw 'The completion log must follow the queue update.'
}

if (
    $Workflow.settings.saveDataSuccessExecution -ne 'all' -or
    $Workflow.settings.saveDataErrorExecution -ne 'all' -or
    $Workflow.settings.saveManualExecutions -ne $true
) {
    throw 'Pilot execution evidence settings are incomplete.'
}

$StartJson = (Get-Node 'Log Workflow Start').parameters.jsonBody
$CompleteJson = (Get-Node 'Log Workflow Completion').parameters.jsonBody

if (-not $StartJson.Contains(':workflow-start')) {
    throw 'Workflow-start idempotency suffix is missing.'
}
if (-not $CompleteJson.Contains(':workflow-completion')) {
    throw 'Workflow-completion idempotency suffix is missing.'
}

Write-Host 'SIS 01 STABILIZED WORKFLOW CHECK: PASS'
Write-Host 'Verified batch routing, item-aware mapping, response parsing, queue retry, deterministic completion order and execution evidence.'
