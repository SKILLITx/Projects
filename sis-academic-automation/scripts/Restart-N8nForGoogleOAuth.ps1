[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$ProjectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $ProjectRoot | Out-Null

$ApiUrl = $env:NGROK_API_URL
if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    $ApiUrl = 'http://127.0.0.1:4040/api/tunnels'
}

try {
    $NgrokStatus = Invoke-RestMethod -Uri $ApiUrl -Method Get -TimeoutSec 10
}
catch {
    throw 'The running ngrok tunnel could not be read. Keep the existing SIS/ngrok runtime running before using this repair.'
}

$HttpsTunnel = @($NgrokStatus.tunnels) |
    Where-Object { $_.public_url -like 'https://*' } |
    Select-Object -First 1

if ($null -eq $HttpsTunnel -or [string]::IsNullOrWhiteSpace([string]$HttpsTunnel.public_url)) {
    throw 'No active HTTPS ngrok tunnel was found.'
}

$PublicUrl = ([string]$HttpsTunnel.public_url).TrimEnd('/')

$RuntimeDirectory = Get-SisRuntimeDirectory -ProjectRoot $ProjectRoot
$N8nPidPath = Join-Path $RuntimeDirectory 'pids\n8n.pid'
$Stopped = Stop-SisPidFileProcess -Path $N8nPidPath
Start-Sleep -Seconds 2

$N8n = & (Join-Path $PSScriptRoot 'Start-N8n.ps1') `
    -WebhookUrl $PublicUrl `
    -EditorBaseUrl $PublicUrl `
    -PassThru

Write-Host 'N8N PUBLIC OAUTH MODE: READY'
Write-Host ("Editor and OAuth callback base: {0}/" -f $PublicUrl)
Write-Host ("Local health address: {0}" -f $N8n.LocalUrl)
Write-Host ("Previous n8n process stopped: {0}" -f $Stopped)
Write-Host 'The ngrok process and its public domain were preserved.'
