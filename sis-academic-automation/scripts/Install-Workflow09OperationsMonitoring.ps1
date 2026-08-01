[CmdletBinding()]
param(
    [string]$TargetRoot = 'D:\AI automation\zaid278-workflows\skill it\Project 1\V2\sis-academic-automation'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$SourceRoot = Split-Path -Parent $PSScriptRoot
$SourcePackage = Join-Path $SourceRoot 'package.json'
if (-not (Test-Path -LiteralPath $SourcePackage -PathType Leaf)) { throw "Package root could not be resolved from $PSScriptRoot" }
$SourceN8n = (Get-Content -LiteralPath $SourcePackage -Raw -Encoding UTF8 | ConvertFrom-Json).dependencies.n8n
if ($SourceN8n -ne '2.4.0') { throw "The Workflow 09 package must pin n8n 2.4.0; found $SourceN8n." }

$ForbiddenPackageFiles = @(
    '.env',
    'portal\config.local.js'
)
foreach ($RelativePath in $ForbiddenPackageFiles) {
    if (Test-Path -LiteralPath (Join-Path $SourceRoot $RelativePath) -PathType Leaf) {
        throw "Forbidden local or secret file is present in the Workflow 09 package: $RelativePath"
    }
}

$TargetRoot = [IO.Path]::GetFullPath($TargetRoot)
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
}

$TargetPackage = Join-Path $TargetRoot 'package.json'
if (Test-Path -LiteralPath $TargetPackage -PathType Leaf) {
    $TargetN8n = (Get-Content -LiteralPath $TargetPackage -Raw -Encoding UTF8 | ConvertFrom-Json).dependencies.n8n
    if ($TargetN8n -ne '2.4.0') { throw "Target repository must pin n8n 2.4.0; found $TargetN8n." }
}

$Files = @(
    'PACKAGE_MANIFEST.sha256',
    'workflows\09-operations-monitoring.json',
    'database\migrations\20260721000300_phase4_workflow09_operations_monitoring.sql',
    'database\queries\workflow09-contract-snapshot.sql',
    'database\queries\workflow09-verification.sql',
    'database\tests\workflow09-operations-monitoring.sql',
    'scripts\Install-Workflow09OperationsMonitoring.ps1',
    'scripts\Test-Workflow09Static.ps1',
    'scripts\Copy-Workflow09ContractSnapshot.ps1',
    'scripts\Copy-Workflow09Migration.ps1',
    'scripts\Copy-Workflow09Verification.ps1',
    'scripts\Run-Workflow09Acceptance.ps1',
    'tests\static\workflow09-operations-monitoring.test.mjs',
    'tests\acceptance\workflow09-operations-monitoring.acceptance.mjs',
    'docs\workflows\09-operations-monitoring.md',
    'docs\testing\workflow09-acceptance.md',
    'PROJECT_STATE.md',
    'CHANGELOG.md'
)

$Missing = @($Files | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $SourceRoot $_) -PathType Leaf)
})
if ($Missing.Count -gt 0) { throw "Package is incomplete. Missing: $($Missing -join ', ')" }

if ($SourceRoot -ne $TargetRoot) {
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $BackupRoot = Join-Path $TargetRoot ".workflow09-backups\$Timestamp"
    foreach ($RelativePath in $Files) {
        $SourcePath = Join-Path $SourceRoot $RelativePath
        $TargetPath = Join-Path $TargetRoot $RelativePath
        if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
            $BackupPath = Join-Path $BackupRoot $RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $BackupPath) -Force | Out-Null
            Copy-Item -LiteralPath $TargetPath -Destination $BackupPath -Force
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $TargetPath) -Force | Out-Null
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    }
}

if (Test-Path -LiteralPath (Join-Path $TargetRoot 'portal\config.local.js') -PathType Leaf) {
    Write-Host 'Existing portal\config.local.js was preserved.'
} else {
    Write-Host 'portal\config.local.js was not supplied or created; restore it locally before live acceptance.'
}
Write-Host 'SIS 09 FILE INSTALL: PASS'
Write-Host "Target: $TargetRoot"
Write-Host 'Next: run scripts\Test-Workflow09Static.ps1 from the target repository.'
