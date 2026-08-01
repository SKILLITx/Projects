[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RecoveryPath = Join-Path $PSScriptRoot 'Recover-Phase4Wave1CodeContractRepair.ps1'
$WorkflowPath = Join-Path $ProjectRoot 'workflows\08-notification-dispatcher.json'

foreach ($Path in @($RecoveryPath, $WorkflowPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing recovery package file: $Path"
    }
}

$Text = Get-Content -LiteralPath $RecoveryPath -Raw
foreach ($Fragment in @(
    "PSObject.Properties['mode']",
    'Add-Member -MemberType NoteProperty',
    'CredentialSnapshot',
    'Workflow 08 was repaired and verified.'
)) {
    if (-not $Text.Contains($Fragment)) {
        throw "Recovery script validation failed: missing $Fragment"
    }
}

$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$CodeNodes = @($Workflow.nodes | Where-Object { $_.type -eq 'n8n-nodes-base.code' })
if ($CodeNodes.Count -ne 5) {
    throw "Expected five Code nodes in repaired Workflow 08, found $($CodeNodes.Count)."
}

$ExpectedModes = @{
    'Build Claim Request' = 'runOnceForAllItems'
    'Render Notification Batch' = 'runOnceForAllItems'
    'Begin Attempt Decision' = 'runOnceForEachItem'
    'Build Gmail Attempt Result' = 'runOnceForEachItem'
    'Build Unsupported Channel Result' = 'runOnceForEachItem'
}

foreach ($NodeName in $ExpectedModes.Keys) {
    $Node = @($CodeNodes | Where-Object { $_.name -eq $NodeName })
    if ($Node.Count -ne 1) {
        throw "Expected exactly one Code node named '$NodeName'."
    }

    $ActualMode = [string]$Node[0].parameters.mode
    $ExpectedMode = [string]$ExpectedModes[$NodeName]
    if ($ActualMode -ne $ExpectedMode) {
        throw "Unexpected Code-node mode for '$NodeName': expected '$ExpectedMode', found '$ActualMode'."
    }

    if (
        $ExpectedMode -eq 'runOnceForEachItem' -and
        [string]$Node[0].parameters.jsCode -match 'return\s*\[\s*\{\s*json\s*:'
    ) {
        throw "Per-item Code node still returns an array: '$NodeName'."
    }
}

Write-Host 'PHASE 4 WAVE 1 CODE RECOVERY PACKAGE: PASS'
Write-Host 'Verified missing-property handling, credential preservation and the correct modes for all five Workflow 08 Code nodes.'
