[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'workflows\05-transcript-delivery.json'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing Workflow 05 JSON: $Path"
}

$Workflow = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$Names = @(
    'Classify Google Doc Creation',
    'Classify PDF Upload',
    'Build Transcript Artifact',
    'Classify Document Registration'
)

foreach ($Name in $Names) {
    $Node = $Workflow.nodes | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($null -eq $Node) {
        throw "Missing node: $Name"
    }
    $Code = [string]$Node.parameters.jsCode
    if (-not $Code.Contains("if(typeof body==='string'){try{body=JSON.parse(body);}catch{}}")) {
        throw "JSON-string response parsing is missing from: $Name"
    }
}

Write-Host 'SIS 05 GOOGLE RESPONSE BODY PARSER FIX CHECK: PASS'
Write-Host 'Verified Google and document RPC classifiers parse JSON-string response bodies.'
