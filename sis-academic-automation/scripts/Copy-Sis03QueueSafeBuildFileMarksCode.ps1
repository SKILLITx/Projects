[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PatchPath = Join-Path $ProjectRoot 'patches\workflow03-build-file-marks-request-queue-safe.js'

if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
    throw "Patch file not found: $PatchPath"
}

Get-Content -LiteralPath $PatchPath -Raw | Set-Clipboard

Write-Host 'SIS 03 QUEUE-SAFE BUILD FILE MARKS CODE: COPIED'
Write-Host "Paste it into the complete Workflow 03 node: Build File Marks Request"
