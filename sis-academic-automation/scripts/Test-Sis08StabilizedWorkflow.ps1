[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\08-notification-dispatcher-stabilized.json'

if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    throw "Missing stabilized Workflow 08: $WorkflowPath"
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
    throw 'Workflow 08 must import inactive.'
}

$WorkflowIdProperty = $Workflow.PSObject.Properties['id']
if ($null -ne $WorkflowIdProperty -and -not [string]::IsNullOrWhiteSpace([string]$WorkflowIdProperty.Value)) {
    throw 'Workflow 08 must import separately and not overwrite the original.'
}

$ExpectedModes = @{
    'Build Claim Request' = 'runOnceForAllItems'
    'Render Notification Batch' = 'runOnceForAllItems'
    'Begin Attempt Decision' = 'runOnceForEachItem'
    'Build Gmail Attempt Result' = 'runOnceForEachItem'
    'Build Unsupported Channel Result' = 'runOnceForEachItem'
    'Validate Delivery Record' = 'runOnceForEachItem'
}

foreach ($Name in $ExpectedModes.Keys) {
    $Node = Get-Node $Name
    if ([string]$Node.parameters.mode -ne [string]$ExpectedModes[$Name]) {
        throw "Unexpected Code-node mode for '$Name'."
    }

    if (
        $ExpectedModes[$Name] -eq 'runOnceForEachItem' -and
        [string]$Node.parameters.jsCode -match 'return\s*\[\s*\{\s*json\s*:'
    ) {
        throw "Per-item Code node returns an array: '$Name'."
    }
}

$Render = Get-Node 'Render Notification Batch'
foreach ($Fragment in @(
    '$input.all()',
    'pairedItem',
    'NOTIFICATION_CLAIM_FAILED',
    'hasNotification: false'
)) {
    if (-not $Render.parameters.jsCode.Contains($Fragment)) {
        throw "Notification batch renderer is missing: $Fragment"
    }
}

$GmailResult = Get-Node 'Build Gmail Attempt Result'
foreach ($Fragment in @(
    'NOTIFICATION_DELIVERY_OUTCOME_UNKNOWN',
    'temporary_failure',
    'permanent_failure',
    'providerMessageId'
)) {
    if (-not $GmailResult.parameters.jsCode.Contains($Fragment)) {
        throw "Gmail outcome classifier is missing: $Fragment"
    }
}

$Gmail = Get-Node 'Send Gmail Message'
if ($Gmail.continueOnFail -ne $true) {
    throw 'Gmail errors must flow to the delivery-outcome classifier.'
}
$RetryProperty = $Gmail.PSObject.Properties['retryOnFail']
if ($null -ne $RetryProperty -and $RetryProperty.Value -eq $true) {
    throw 'Gmail must not use node-level retries because the database owns attempts.'
}

foreach ($Name in @(
    'Claim Notification Batch',
    'Begin Delivery Attempt',
    'Record Delivery Attempt'
)) {
    $Node = Get-Node $Name
    if ($Node.retryOnFail -ne $true -or $Node.maxTries -ne 3) {
        throw "$Name must retry three times."
    }
    if ($Node.parameters.options.timeout -ne 15000) {
        throw "$Name must have a 15-second timeout."
    }
}

$RecordConnections = $Workflow.connections.'Record Delivery Attempt'.main[0]
if (
    $RecordConnections.Count -ne 1 -or
    $RecordConnections[0].node -ne 'Validate Delivery Record'
) {
    throw 'Delivery recording must be validated before completion logging.'
}

$ValidateConnections = $Workflow.connections.'Validate Delivery Record'.main[0]
if (
    $ValidateConnections.Count -ne 1 -or
    $ValidateConnections[0].node -ne 'Log Dispatcher Completion'
) {
    throw 'Completion logging must follow durable delivery recording.'
}

$StartBody = (Get-Node 'Log Dispatcher Start').parameters.jsonBody
$EmptyBody = (Get-Node 'Log Empty Dispatcher Run').parameters.jsonBody
$DedupBody = (Get-Node 'Log Deduplicated Attempt').parameters.jsonBody
$CompletionBody = (Get-Node 'Log Dispatcher Completion').parameters.jsonBody

foreach ($Pair in @(
    @($StartBody, ':start'),
    @($EmptyBody, ':empty'),
    @($DedupBody, ':deduplicated:'),
    @($CompletionBody, ':delivery:')
)) {
    if (-not ([string]$Pair[0]).Contains([string]$Pair[1])) {
        throw "Unique dispatcher log idempotency suffix is missing: $($Pair[1])"
    }
}

if (
    $Workflow.settings.saveDataSuccessExecution -ne 'all' -or
    $Workflow.settings.saveDataErrorExecution -ne 'all' -or
    $Workflow.settings.saveManualExecutions -ne $true
) {
    throw 'Workflow 08 pilot execution evidence settings are incomplete.'
}

Write-Host 'SIS 08 STABILIZED WORKFLOW CHECK: PASS'
Write-Host 'Verified Code-node modes, batch item linking, conservative Gmail outcome handling, RPC retries, unique logging keys and durable delivery recording.'
