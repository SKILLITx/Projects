[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'google\provisioning\SIS-Wave1ConfigHelper.gs'
Set-Clipboard -Value (Get-Content -LiteralPath $Path -Raw)
Write-Host 'Wave 1 Google configuration helper copied to the clipboard.'
