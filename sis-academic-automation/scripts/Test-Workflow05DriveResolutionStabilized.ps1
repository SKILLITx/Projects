[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'workflows\05-transcript-delivery-drive-resolution-stabilized.json'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing stabilized Workflow 05 JSON: $Path"
}

$Workflow = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($Name in @(
    'Resolve Created Google Doc',
    'Resolve Uploaded Transcript PDF',
    'Classify Google Doc Creation',
    'Classify PDF Upload'
)) {
    if ($null -eq ($Workflow.nodes | Where-Object { $_.name -eq $Name } | Select-Object -First 1)) {
        throw "Missing node: $Name"
    }
}

$DocNext = $Workflow.connections.'Create Transcript Google Doc'.main[0][0].node
$PdfNext = $Workflow.connections.'Upload Transcript PDF'.main[0][0].node

if ($DocNext -ne 'Resolve Created Google Doc') {
    throw 'Google Doc creation is not connected to deterministic Drive resolution.'
}
if ($PdfNext -ne 'Resolve Uploaded Transcript PDF') {
    throw 'PDF upload is not connected to deterministic Drive resolution.'
}

$DocClassifier = ($Workflow.nodes | Where-Object { $_.name -eq 'Classify Google Doc Creation' } | Select-Object -First 1).parameters.jsCode
$PdfClassifier = ($Workflow.nodes | Where-Object { $_.name -eq 'Classify PDF Upload' } | Select-Object -First 1).parameters.jsCode

if (-not $DocClassifier.Contains('body?.files')) {
    throw 'Google Doc classifier does not read Drive list results.'
}
if (-not $PdfClassifier.Contains('body?.files')) {
    throw 'PDF classifier does not read Drive list results.'
}

Write-Host 'SIS 05 DRIVE RESOLUTION STABILIZED CHECK: PASS'
Write-Host 'Verified deterministic Google Doc and PDF resolution after side-effecting upload calls.'
