[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Path = Join-Path $ProjectRoot 'database\tests\phase4-wave1-hosted-verification.sql'
Set-Clipboard -Value (Get-Content -LiteralPath $Path -Raw)
Write-Host 'Phase 4 Wave 1 hosted verification SQL copied to the clipboard.'
