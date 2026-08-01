[CmdletBinding()]
param([switch]$Quiet)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$projectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $projectRoot -AllowMissing | Out-Null
$runtimeDirectory = Get-SisRuntimeDirectory -ProjectRoot $projectRoot
$pidDirectory = Join-Path $runtimeDirectory 'pids'

$n8nStopped = Stop-SisPidFileProcess -Path (Join-Path $pidDirectory 'n8n.pid')
$ngrokStopped = Stop-SisPidFileProcess -Path (Join-Path $pidDirectory 'ngrok.pid')
Remove-Item -LiteralPath (Join-Path $runtimeDirectory 'active-webhook-url.txt') -Force -ErrorAction SilentlyContinue

if (-not $Quiet) {
    Write-Host ("n8n stopped: {0}" -f $n8nStopped)
    Write-Host ("ngrok stopped: {0}" -f $ngrokStopped)
}
