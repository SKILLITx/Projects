[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$ProjectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $ProjectRoot | Out-Null

$Port = 5678
if (-not [string]::IsNullOrWhiteSpace($env:N8N_PORT)) { $Port = [int]$env:N8N_PORT }
if (Test-SisTcpPort -Port $Port) {
  throw "Port $Port is in use. Stop SIS with scripts\Stop-SIS.ps1 before importing workflows."
}

$N8nCommand = Get-SisN8nCommand -ProjectRoot $ProjectRoot
$Files = @(
  'workflows\01-student-intake.json',
  'workflows\02-enrollment-lifecycle.json',
  'workflows\08-notification-dispatcher.json'
)

foreach ($RelativePath in $Files) {
  $FullPath = Join-Path $ProjectRoot $RelativePath
  & $N8nCommand import:workflow --input=$FullPath
  if ($LASTEXITCODE -ne 0) { throw "n8n import failed for $RelativePath" }
}

Write-Host 'PHASE 4 WAVE 1 IMPORT: PASS'
Write-Host 'Imported three inactive workflows. Bind credentials and verify node configuration before activation.'
