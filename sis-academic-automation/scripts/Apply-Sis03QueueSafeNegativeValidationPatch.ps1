[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\03-marks-intake-complete-stabilized.json'
$PatchPath = Join-Path $ProjectRoot 'patches\workflow03-build-file-marks-request-queue-safe.js'

if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    throw "Workflow file not found: $WorkflowPath"
}

if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
    throw "Patch file not found: $PatchPath"
}

$BackupPath = "$WorkflowPath.before-queue-safe-negative-validation"
Copy-Item -LiteralPath $WorkflowPath -Destination $BackupPath -Force

$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$Nodes = @($Workflow.nodes | Where-Object { $_.name -eq 'Build File Marks Request' })

if ($Nodes.Count -ne 1) {
    throw "Expected exactly one 'Build File Marks Request' node."
}

$PatchedCode = Get-Content -LiteralPath $PatchPath -Raw
$Nodes[0].parameters.jsCode = $PatchedCode.TrimEnd()
$Nodes[0].notes = 'Aggregates extracted rows and converts duplicate or malformed file data into durable failed queue outcomes instead of terminating the execution.'

$Json = $Workflow | ConvertTo-Json -Depth 100
$Utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($WorkflowPath, $Json + [Environment]::NewLine, $Utf8)

Write-Host 'SIS 03 QUEUE-SAFE NEGATIVE VALIDATION PATCH: APPLIED'
Write-Host "Backup: $BackupPath"
