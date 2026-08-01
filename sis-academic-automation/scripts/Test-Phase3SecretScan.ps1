[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Validator = Join-Path $PSScriptRoot 'Test-Phase3Package.ps1'
$ProbeDirectory = Join-Path $ProjectRoot 'tests\static'
$ProbePath = Join-Path $ProbeDirectory '.phase3-secret-scan-probe.env'

New-Item -ItemType Directory -Path $ProbeDirectory -Force | Out-Null

try {
  & $Validator
  if (-not $?) {
    throw 'The Phase 3 validator failed before the regression probe was created.'
  }

  # Construct the fake credential at runtime so the regression script itself
  # does not contain a secret-shaped literal that the static scanner should reject.
  $VariableName = 'SUPABASE_' + 'SECRET_KEY'
  $SecretPrefix = 'sb_' + 'secret_'
  $ProbeValue = $SecretPrefix + 'regression_probe_' + ('a' * 24)
  $ProbeContent = $VariableName + '=' + $ProbeValue

  [IO.File]::WriteAllText(
    $ProbePath,
    $ProbeContent,
    [Text.UTF8Encoding]::new($false)
  )

  $ProbeWasDetected = $false
  try {
    & $Validator
  }
  catch {
    if ($_.Exception.Message -match 'Potential secret') {
      $ProbeWasDetected = $true
    }
    else {
      throw
    }
  }

  if (-not $ProbeWasDetected) {
    throw 'The validator did not detect a runtime-generated secret-shaped value in a portable test file.'
  }
}
finally {
  if (Test-Path -LiteralPath $ProbePath) {
    Remove-Item -LiteralPath $ProbePath -Force
  }
}

& $Validator
if (-not $?) {
  throw 'The Phase 3 validator failed after the regression probe was removed.'
}

Write-Host 'PHASE 3 SECRET-SCAN REGRESSION: PASS'
Write-Host 'Local secrets were excluded, documented placeholders were accepted, and a runtime-generated portable secret was detected.'
