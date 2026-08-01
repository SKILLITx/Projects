[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$projectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $projectRoot | Out-Null
$runtimeDirectory = Get-SisRuntimeDirectory -ProjectRoot $projectRoot

$port = 5678
if (-not [string]::IsNullOrWhiteSpace($env:N8N_PORT)) { $port = [int]$env:N8N_PORT }
$localUrl = "http://127.0.0.1:$port/"
$local = Invoke-SisHttpProbe -BaseUrl $localUrl
if (-not $local.Success) { throw "Local n8n probe failed at $localUrl" }
Write-Host ("[PASS] Local n8n: {0} returned HTTP {1}" -f $local.Url, $local.StatusCode)

$activeUrlPath = Join-Path $runtimeDirectory 'active-webhook-url.txt'
if (-not (Test-Path -LiteralPath $activeUrlPath -PathType Leaf)) {
    throw 'No active webhook URL file exists. Start the full runtime with Start-SIS.ps1.'
}
$publicUrl = (Get-Content -LiteralPath $activeUrlPath | Select-Object -First 1).Trim()
$public = Invoke-SisHttpProbe -BaseUrl $publicUrl
if (-not $public.Success) { throw "Public n8n probe failed at $publicUrl" }
Write-Host ("[PASS] Public n8n: {0} returned HTTP {1}" -f $public.Url, $public.StatusCode)
Write-Host 'Runtime health validation passed.'
