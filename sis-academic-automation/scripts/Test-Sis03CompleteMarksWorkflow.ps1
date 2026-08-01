[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\03-marks-intake-complete-stabilized.json'
$CsvPath = Join-Path $ProjectRoot 'tests\acceptance\workflow03-fin-marks-upload-template.csv'
$XlsxPath = Join-Path $ProjectRoot 'tests\acceptance\workflow03-fin-marks-upload-template.xlsx'

foreach ($Path in @($WorkflowPath, $CsvPath, $XlsxPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
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
    throw 'Complete Workflow 03 must import inactive.'
}

$WorkflowIdProperty = $Workflow.PSObject.Properties['id']
if ($null -ne $WorkflowIdProperty -and -not [string]::IsNullOrWhiteSpace([string]$WorkflowIdProperty.Value)) {
    throw 'Complete Workflow 03 must import separately.'
}

foreach ($Name in @(
    'Manual Marks Queue Trigger',
    'Marks File Queue Trigger'
)) {
    $Node = Get-Node $Name
    if ($Node.parameters.options.dataLocationOnSheet.values.range -ne 'A1:P') {
        throw "$Name must read A1:P."
    }
}

$ManualNormalizer = Get-Node 'Normalize Manual Marks Queue Row'
foreach ($Fragment in @(
    "operation === 'marks.batch.submit'",
    'Marks â€” one line per student',
    'VALIDATION_DUPLICATE_STUDENT_NUMBER',
    'runOnceForEachItem'
)) {
    if ($Fragment -eq 'runOnceForEachItem') {
        if ($ManualNormalizer.parameters.mode -ne $Fragment) {
            throw 'Manual normalizer has the wrong Code-node mode.'
        }
    }
    elseif (-not ([string]$ManualNormalizer.parameters.jsCode).Contains($Fragment)) {
        throw "Manual normalizer is missing: $Fragment"
    }
}

$FileNormalizer = Get-Node 'Normalize Marks File Queue Row'
foreach ($Fragment in @(
    "operation === 'marks.file.submit'",
    'Uploaded CSV or Excel Google Drive URL',
    'VALIDATION_MARKS_FILE_TYPE',
    "['csv', 'xlsx', 'xls']"
)) {
    if (-not ([string]$FileNormalizer.parameters.jsCode).Contains($Fragment)) {
        throw "File normalizer is missing: $Fragment"
    }
}

$Drive = Get-Node 'Download Marks File'
if (
    $Drive.type -ne 'n8n-nodes-base.googleDrive' -or
    $Drive.typeVersion -ne 3 -or
    $Drive.parameters.resource -ne 'file' -or
    $Drive.parameters.operation -ne 'download' -or
    $Drive.parameters.options.binaryPropertyName -ne 'data'
) {
    throw 'Google Drive download node is not configured for n8n 2.4.0.'
}
if ($Drive.continueOnFail -ne $true) {
    throw 'Google Drive errors must reach the queue outcome classifier.'
}

$ExpectedExtractOperations = @{
    'Extract CSV Marks' = 'csv'
    'Extract XLSX Marks' = 'xlsx'
    'Extract XLS Marks' = 'xls'
}

foreach ($Name in $ExpectedExtractOperations.Keys) {
    $Node = Get-Node $Name
    if (
        $Node.type -ne 'n8n-nodes-base.extractFromFile' -or
        $Node.typeVersion -ne 1.1 -or
        $Node.parameters.operation -ne $ExpectedExtractOperations[$Name] -or
        $Node.parameters.binaryPropertyName -ne 'data' -or
        $Node.parameters.options.headerRow -ne $true
    ) {
        throw "Native extraction configuration is invalid for '$Name'."
    }
    if ($Node.continueOnFail -ne $true) {
        throw "$Name parsing errors must reach queue classification."
    }
}

$Builder = Get-Node 'Build File Marks Request'
if ($Builder.parameters.mode -ne 'runOnceForAllItems') {
    throw 'File marks request builder must aggregate all extracted rows.'
}
foreach ($Fragment in @(
    '$input.all()',
    'student_number',
    'marks_obtained',
    'is_absent',
    'is_missing',
    'VALIDATION_DUPLICATE_STUDENT_NUMBER'
)) {
    if (-not ([string]$Builder.parameters.jsCode).Contains($Fragment)) {
        throw "File request builder is missing: $Fragment"
    }
}

foreach ($Name in @(
    'Log File Workflow Start',
    'Submit File Marks RPC',
    'Log File Workflow Completion'
)) {
    $Node = Get-Node $Name
    if ($Node.parameters.options.timeout -ne 15000) {
        throw "$Name must have a 15-second timeout."
    }
    if ($Node.retryOnFail -ne $true -or $Node.maxTries -ne 3) {
        throw "$Name must use three bounded retries."
    }
}

$UpdateConnections = $Workflow.connections.'Update File Automation Queue'.main[0]
if (
    $UpdateConnections.Count -ne 1 -or
    $UpdateConnections[0].node -ne 'Log File Workflow Completion'
) {
    throw 'File completion logging must follow the durable queue update.'
}

$CsvRows = Import-Csv -LiteralPath $CsvPath
if ($CsvRows.Count -ne 8) {
    throw 'CSV acceptance template must contain eight marks rows.'
}

foreach ($Header in @('student_number', 'marks', 'absent', 'missing', 'remarks')) {
    if (-not ($CsvRows[0].PSObject.Properties.Name -contains $Header)) {
        throw "CSV acceptance template is missing header: $Header"
    }
}

if (
    $Workflow.settings.saveDataSuccessExecution -ne 'all' -or
    $Workflow.settings.saveDataErrorExecution -ne 'all' -or
    $Workflow.settings.saveManualExecutions -ne $true
) {
    throw 'Complete Workflow 03 evidence settings are incomplete.'
}

Write-Host 'SIS 03 COMPLETE MARKS WORKFLOW CHECK: PASS'
Write-Host 'Verified manual and file triggers, Drive download, native CSV/XLS/XLSX extraction, row aggregation, queue failure handling, RPC retries and acceptance templates.'
