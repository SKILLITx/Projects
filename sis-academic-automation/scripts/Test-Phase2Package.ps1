[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LedgerPath = Join-Path $ProjectRoot 'database\schema\migration-checksums.json'
if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) { throw "Missing checksum ledger: $LedgerPath" }
$Ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$Failures = New-Object System.Collections.Generic.List[string]
foreach ($Property in $Ledger.migrations.PSObject.Properties) {
    $MigrationPath = Join-Path $ProjectRoot (Join-Path 'supabase\migrations' $Property.Name)
    if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf)) { $Failures.Add("Missing migration: $($Property.Name)"); continue }
    $Actual = (Get-FileHash -LiteralPath $MigrationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $Expected = ([string]$Property.Value).ToLowerInvariant()
    if ($Actual -ne $Expected) { $Failures.Add("Checksum mismatch: $($Property.Name)") }
}
if ($Failures.Count -gt 0) { $Failures | ForEach-Object { Write-Error $_ }; throw "PHASE 2 PACKAGE STATIC CHECK: FAIL ($($Failures.Count) issue(s))" }
Write-Host "PHASE 2 PACKAGE STATIC CHECK: PASS"
$MigrationCount = @($Ledger.migrations.PSObject.Properties).Count
Write-Host "Verified $MigrationCount ordered migration file(s)."
