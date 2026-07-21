[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $ProjectRoot 'google\provisioning\SIS-WorkspaceProvisioner.gs'
Set-Clipboard -Value (Get-Content -LiteralPath $Source -Raw)
Write-Host 'Phase 3 Google Workspace provisioner copied to the clipboard.'
Write-Host 'Create a standalone Apps Script project, paste into Code.gs, and run provisionPhase3Workspace.'
