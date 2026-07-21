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
$Node = $Workflow.nodes | Where-Object { $_.name -eq 'Normalize Transcript Request' } | Select-Object -First 1

if ($null -eq $Node) {
    throw 'Normalize Transcript Request node was not found.'
}

$Code = [string]$Node.parameters.jsCode
$Expected = 'const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;'
$Forbidden = '[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}'

if (-not $Code.Contains($Expected)) {
    throw 'PostgreSQL-compatible canonical UUID validation was not installed.'
}

if ($Code.Contains($Forbidden)) {
    throw 'The obsolete RFC version/variant restriction is still present.'
}

Write-Host 'SIS 05 POSTGRESQL UUID VALIDATION FIX CHECK: PASS'
Write-Host 'Verified canonical PostgreSQL UUID acceptance without weakening UUID shape validation.'
