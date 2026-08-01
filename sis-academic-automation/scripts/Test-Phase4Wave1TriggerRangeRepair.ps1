[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$WorkflowFiles = @(
  'workflows\01-student-intake.json',
  'workflows\02-enrollment-lifecycle.json'
)

foreach ($RelativePath in $WorkflowFiles) {
  $Path = Join-Path $ProjectRoot $RelativePath
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing repaired workflow: $RelativePath"
  }

  $Workflow = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $Triggers = @($Workflow.nodes | Where-Object { $_.type -eq 'n8n-nodes-base.googleSheetsTrigger' })
  if ($Triggers.Count -ne 1) {
    throw "$RelativePath must contain exactly one Google Sheets Trigger."
  }

  $Range = $Triggers[0].parameters.options.dataLocationOnSheet.values.range
  if ($Range -ne 'A1:P') {
    throw "$RelativePath has invalid trigger range '$Range'; expected 'A1:P'."
  }

  if ($Range -match '^[A-Z]+:[A-Z]+$') {
    throw "$RelativePath still contains a rowless A1 range."
  }
}

Write-Host 'PHASE 4 WAVE 1 TRIGGER RANGE REPAIR: PASS'
Write-Host 'Student and enrollment queue triggers now use A1:P, preventing the invalid A0:P0 request.'
