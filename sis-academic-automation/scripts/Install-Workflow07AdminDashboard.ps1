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
if ($SourceN8n -ne '2.4.0') { throw "The Workflow 07 package must pin n8n 2.4.0; found $SourceN8n." }

$ForbiddenPackageFiles = @(
    '.env',
    'portal\config.local.js'
)
foreach ($RelativePath in $ForbiddenPackageFiles) {
    if (Test-Path -LiteralPath (Join-Path $SourceRoot $RelativePath) -PathType Leaf) {
        throw "Forbidden local or secret file is present in the Workflow 07 package: $RelativePath"
    }
}

$TargetRoot = [IO.Path]::GetFullPath($TargetRoot)
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) { New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null }

$TargetPackage = Join-Path $TargetRoot 'package.json'
if (Test-Path -LiteralPath $TargetPackage -PathType Leaf) {
    $TargetN8n = (Get-Content -LiteralPath $TargetPackage -Raw -Encoding UTF8 | ConvertFrom-Json).dependencies.n8n
    if ($TargetN8n -ne '2.4.0') { throw "Target repository must pin n8n 2.4.0; found $TargetN8n." }
}

$Files = @(
    'PACKAGE_MANIFEST.sha256',
    'workflows\07-admin-dashboard.json',
    'database\migrations\20260721000200_phase4_workflow07_admin_search_dashboard_complete.sql',
    'database\queries\workflow07-contract-snapshot.sql',
    'database\queries\workflow07-verification.sql',
    'database\tests\workflow07-admin-dashboard.sql',
    'portal\index.html',
    'portal\app.js',
    'portal\styles.css',
    'scripts\Install-Workflow07AdminDashboard.ps1',
    'scripts\Test-Workflow07Static.ps1',
    'scripts\Copy-Workflow07ContractSnapshot.ps1',
    'scripts\Copy-Workflow07Migration.ps1',
    'scripts\Copy-Workflow07Verification.ps1',
    'scripts\Run-Workflow07Acceptance.ps1',
    'tests\static\workflow07-admin-dashboard.test.mjs',
    'tests\acceptance\workflow07-admin-dashboard.acceptance.mjs',
    'docs\workflows\07-admin-dashboard.md',
    'docs\testing\workflow07-acceptance.md',
    'PROJECT_STATE.md',
    'CHANGELOG.md'
)

$Missing = @($Files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $SourceRoot $_) -PathType Leaf) })
if ($Missing.Count -gt 0) { throw "Package is incomplete. Missing: $($Missing -join ', ')" }

if ($SourceRoot -ne $TargetRoot) {
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $BackupRoot = Join-Path $TargetRoot ".workflow07-backups\$Timestamp"
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

    $OldDoc = Join-Path $TargetRoot 'docs\workflows\07-admin-search-dashboard.md'
    if (Test-Path -LiteralPath $OldDoc -PathType Leaf) {
        $OldDocBackup = Join-Path $BackupRoot 'docs\workflows\07-admin-search-dashboard.md'
        New-Item -ItemType Directory -Path (Split-Path -Parent $OldDocBackup) -Force | Out-Null
        Copy-Item -LiteralPath $OldDoc -Destination $OldDocBackup -Force
        Remove-Item -LiteralPath $OldDoc -Force
    }
}

if (Test-Path -LiteralPath (Join-Path $TargetRoot 'portal\config.local.js') -PathType Leaf) {
    Write-Host 'Existing portal\config.local.js was preserved.'
} else {
    Write-Host 'portal\config.local.js was not supplied or created; initialize it locally before live portal tests.'
}
Write-Host 'SIS 07 FILE INSTALL: PASS'
Write-Host "Target: $TargetRoot"
Write-Host 'Next: run scripts\Test-Workflow07Static.ps1 from the target repository.'
