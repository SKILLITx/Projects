[CmdletBinding()]
param(
  [string]$Repository = "D:\AI automation\zaid278-workflows\skill it\Project 1\V2\sis-academic-automation"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Repository)) { throw "Repository not found: $Repository" }
Set-Location -LiteralPath $Repository

$checks = [ordered]@{}
$warnings = New-Object System.Collections.Generic.List[string]

$packageJsonPath = Join-Path $Repository 'package.json'
if (-not (Test-Path -LiteralPath $packageJsonPath)) { throw "package.json not found: $packageJsonPath" }
$packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
$n8nVersion = $null
if ($packageJson.dependencies -and $packageJson.dependencies.n8n) { $n8nVersion = [string]$packageJson.dependencies.n8n }
if (-not $n8nVersion -and $packageJson.devDependencies -and $packageJson.devDependencies.n8n) { $n8nVersion = [string]$packageJson.devDependencies.n8n }
$checks.n8n_version_exact_2_4_0 = ($n8nVersion -eq '2.4.0')

$nodeRoot = Join-Path $Repository 'node_modules\n8n-nodes-base\dist\nodes'
$checks.node_catalogue_present = Test-Path -LiteralPath $nodeRoot
if (-not $checks.node_catalogue_present) { throw "Installed n8n node catalogue not found: $nodeRoot" }

function Find-NodeImplementation {
  param([string[]]$Patterns)
  foreach ($pattern in $Patterns) {
    $match = Get-ChildItem -LiteralPath $nodeRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern } | Select-Object -First 1
    if ($match) { return $match.FullName }
  }
  return $null
}

$nodeFiles = [ordered]@{
  error_trigger = Find-NodeImplementation @('*ErrorTrigger*.node.js','*ErrorTrigger*.js')
  code = Find-NodeImplementation @('Code.node.js','*Code*.node.js')
  http_request = Find-NodeImplementation @('*HttpRequest*.node.js','*HttpRequest*.js')
  if_node = Find-NodeImplementation @('If.node.js','*IfV*.node.js','*If*.node.js')
  merge = Find-NodeImplementation @('Merge.node.js','*MergeV*.node.js','*Merge*.node.js')
  switch = Find-NodeImplementation @('Switch.node.js','*SwitchV*.node.js','*Switch*.node.js')
}
foreach ($key in @($nodeFiles.Keys)) { $checks["node_$key`_present"] = -not [string]::IsNullOrWhiteSpace([string]$nodeFiles[$key]) }

$errorTriggerText = ''
if ($nodeFiles.error_trigger) { $errorTriggerText = Get-Content -LiteralPath $nodeFiles.error_trigger -Raw -ErrorAction SilentlyContinue }
$checks.error_trigger_identity_present = ($errorTriggerText -match 'errorTrigger')

$workflowDir = Join-Path $Repository 'workflows'
if (-not (Test-Path -LiteralPath $workflowDir)) { throw "Workflow directory not found: $workflowDir" }
$workflowSummaries = New-Object System.Collections.Generic.List[object]
$cryptoReferences = New-Object System.Collections.Generic.List[object]
$existingErrorHandlers = New-Object System.Collections.Generic.List[object]
$parseFailures = New-Object System.Collections.Generic.List[string]

Get-ChildItem -LiteralPath $workflowDir -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
  try {
    $workflow = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    $nodes = @($workflow.nodes)
    $types = @($nodes | ForEach-Object { [string]$_.type } | Where-Object { $_ } | Sort-Object -Unique)
    $active = $false
    if ($null -ne $workflow.active) { $active = [bool]$workflow.active }
    $name = [string]$workflow.name
    $workflowSummaries.Add([pscustomobject]@{ file=$_.Name; name=$name; active=$active; node_types=$types })
    $hasErrorTrigger = @($types | Where-Object { $_ -match 'errorTrigger' }).Count -gt 0
    if ($hasErrorTrigger -or $name -match '^SIS 10\b') { $existingErrorHandlers.Add([pscustomobject]@{ file=$_.Name; name=$name; active=$active }) }
    $connectionText = ''
    if ($workflow.connections) { $connectionText = $workflow.connections | ConvertTo-Json -Depth 100 -Compress }
    foreach ($node in @($nodes | Where-Object { [string]$_.type -match 'crypto' })) {
      $connected = $false
      if ($connectionText -and $node.name) { $connected = $connectionText -match [regex]::Escape([string]$node.name) }
      $cryptoReferences.Add([pscustomobject]@{ file=$_.Name; workflow=$name; active=$active; node=[string]$node.name; type=[string]$node.type; connected=$connected })
    }
  } catch {
    $parseFailures.Add($_.Name)
  }
}

$checks.workflow_json_parse = ($parseFailures.Count -eq 0)

$runtimeCataloguePath = Join-Path $env:TEMP ("sis-workflow10-runtime-catalogue-" + [guid]::NewGuid().ToString('N') + '.json')
$runtimeCatalogue = $null
$runtimeHelper = Join-Path $Repository 'scripts\Inspect-N8nRuntimeCatalogue.mjs'
if (Test-Path -LiteralPath $runtimeHelper) {
  try {
    & node $runtimeHelper $Repository $runtimeCataloguePath
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $runtimeCataloguePath)) {
      $runtimeCatalogue = Get-Content -LiteralPath $runtimeCataloguePath -Raw | ConvertFrom-Json
      if (-not $runtimeCatalogue.available -and $runtimeCatalogue.warning) { $warnings.Add([string]$runtimeCatalogue.warning) }
      if ($runtimeCatalogue.available) {
        $runtimeActiveErrorHandlers = @($runtimeCatalogue.error_handlers | Where-Object { $_.active })
        if ($runtimeActiveErrorHandlers.Count -gt 0) {
          $checks.no_active_runtime_workflow10_duplicate = $false
          $warnings.Add('The live n8n SQLite catalogue contains an active Error Trigger/Workflow 10-like workflow.')
        } else {
          $checks.no_active_runtime_workflow10_duplicate = $true
        }
      } else {
        $checks.no_active_runtime_workflow10_duplicate = $true
      }
    }
  } catch {
    $warnings.Add('Live n8n workflow catalogue inspection was unavailable; repository workflow exports were inspected instead.')
  } finally {
    Remove-Item -LiteralPath $runtimeCataloguePath -Force -ErrorAction SilentlyContinue
  }
}

$activeErrorHandlers = @($existingErrorHandlers | Where-Object { $_.active })
$checks.no_active_workflow10_duplicate = ($activeErrorHandlers.Count -eq 0)
if ($cryptoReferences.Count -gt 0) { $warnings.Add("Legacy Crypto-node references found: $($cryptoReferences.Count). Review active/connected classification before final integration; do not copy them into Workflow 10.") }
if ($activeErrorHandlers.Count -gt 0) { $warnings.Add("An active Error Trigger/Workflow 10-like workflow already exists and must be resolved before building the stabilized Workflow 10.") }

$failedChecks = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value } | ForEach-Object { $_.Key })
$status = 'PASS'
if ($failedChecks.Count -gt 0) { $status = 'FAIL' }

$evidenceDir = Join-Path $Repository 'evidence'
if (-not (Test-Path -LiteralPath $evidenceDir)) { New-Item -ItemType Directory -Path $evidenceDir | Out-Null }
$stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH-mm-ss-fffZ')
$evidencePath = Join-Path $evidenceDir ("workflow10-local-preflight-$stamp.json")
$result = [ordered]@{
  status = $status
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  repository = $Repository
  n8n_version = $n8nVersion
  checks = $checks
  failed_checks = $failedChecks
  node_implementations = $nodeFiles
  workflow_summaries = $workflowSummaries
  runtime_workflow_catalogue = $runtimeCatalogue
  existing_error_handlers = $existingErrorHandlers
  unsupported_crypto_references = $cryptoReferences
  warnings = $warnings
}
$result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

Write-Host "Workflow 10 local preflight: $status"
Write-Host "Checks passed: $($checks.Count - $failedChecks.Count)"
Write-Host "Checks failed: $($failedChecks.Count)"
Write-Host "Warnings: $($warnings.Count)"
Write-Host "Evidence written: $evidencePath"
foreach ($warning in $warnings) { Write-Host "WARNING: $warning" }
if ($status -ne 'PASS') { throw "SIS 10 LOCAL PREFLIGHT: FAIL - $($failedChecks -join ', ')" }
Write-Host 'SIS 10 LOCAL PREFLIGHT: PASS'
