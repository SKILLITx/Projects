[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$Required = @(
  'supabase\migrations\20260717000900_phase4_wave1_form_integration.sql',
  'workflows\01-student-intake.json',
  'workflows\02-enrollment-lifecycle.json',
  'workflows\08-notification-dispatcher.json',
  'database\tests\phase4-wave1-hosted-verification.sql',
  'database\schema\migration-checksums.json',
  'docs\workflows\01-student-intake.md',
  'docs\workflows\02-enrollment-lifecycle.md',
  'docs\workflows\08-notification-dispatcher.md',
  'docs\setup\09-phase4-wave1-credential-binding.md',
  'tests\static\validate-phase4-wave1.js',
  'tests\static\test-wave1-normalizers.js'
)
foreach ($Relative in $Required) {
  if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $Relative) -PathType Leaf)) {
    throw "Missing Phase 4 Wave 1 file: $Relative"
  }
}

$LedgerPath = Join-Path $ProjectRoot 'database\schema\migration-checksums.json'
$Ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
foreach ($Property in @($Ledger.migrations.PSObject.Properties)) {
  $MigrationPath = Join-Path $ProjectRoot ('supabase\migrations\' + $Property.Name)
  if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf)) {
    throw "Missing migration listed in checksum ledger: $($Property.Name)"
  }
  $Hash = (Get-FileHash -LiteralPath $MigrationPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($Hash -ne ([string]$Property.Value).ToLowerInvariant()) {
    throw "Migration checksum mismatch: $($Property.Name)"
  }
}

node (Join-Path $ProjectRoot 'tests\static\validate-phase4-wave1.js')
if ($LASTEXITCODE -ne 0) { throw 'Wave 1 workflow validation failed.' }

node (Join-Path $ProjectRoot 'tests\static\test-wave1-normalizers.js')
if ($LASTEXITCODE -ne 0) { throw 'Wave 1 normalizer regression test failed.' }

$PortableFiles = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File | Where-Object {
  $_.FullName -notmatch '[\\/](node_modules|\.runtime|\.git)[\\/]' -and
  $_.Name -ne '.env' -and
  $_.FullName -notmatch '[\\/]portal[\\/]config\.local\.js$'
}
foreach ($File in $PortableFiles) {
  $Text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $Text) { continue }
  if ($Text -match 'sb_secret_[A-Za-z0-9_-]{16,}' -or
      $Text -match 'AIza[0-9A-Za-z_-]{20,}' -or
      $Text -match '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----') {
    throw "Potential secret detected in portable file: $($File.FullName)"
  }
}

Write-Host 'PHASE 4 WAVE 1 PACKAGE CHECK: PASS'
Write-Host 'Verified migration 009, nine migration checksums, three workflow exports, documentation, tests and secret boundaries.'
