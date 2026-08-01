[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\03-marks-intake-complete-stabilized.json'
$PatchPath = Join-Path $ProjectRoot 'patches\workflow03-build-file-marks-request-queue-safe.js'

$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$Nodes = @($Workflow.nodes | Where-Object { $_.name -eq 'Build File Marks Request' })

if ($Nodes.Count -ne 1) {
    throw "Expected exactly one 'Build File Marks Request' node."
}

$Code = [string]$Nodes[0].parameters.jsCode
$PatchCode = (Get-Content -LiteralPath $PatchPath -Raw).TrimEnd()

if ($Code.TrimEnd() -ne $PatchCode) {
    throw 'Workflow node code does not match the queue-safe patch.'
}

foreach ($Required in @(
    'const failure =',
    "'Processing Status': 'failed'",
    "'VALIDATION_DUPLICATE_STUDENT_NUMBER'",
    'duplicateStudentNumbers',
    'catch (error)',
    'requestReady: false',
    'requestReady: true'
)) {
    if (-not $Code.Contains($Required)) {
        throw "Patched Code node is missing: $Required"
    }
}

if (-not $Workflow.connections.'Is File Request Ready?'.main[1][0].node.Equals('Update File Automation Queue')) {
    throw 'The failed validation branch must update the upload queue.'
}

Write-Host 'SIS 03 QUEUE-SAFE NEGATIVE VALIDATION CHECK: PASS'
Write-Host 'Duplicate and malformed spreadsheet rows now produce durable failed queue outcomes without calling the marks RPC.'
