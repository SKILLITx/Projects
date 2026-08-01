[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$projectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $projectRoot | Out-Null

& (Join-Path $PSScriptRoot 'Test-Environment.ps1') | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Environment validation failed.' }

$ngrok = $null
$n8n = $null
try {
    $ngrok = & (Join-Path $PSScriptRoot 'Start-Ngrok.ps1') -PassThru
    $n8n = & (Join-Path $PSScriptRoot 'Start-N8n.ps1') -WebhookUrl $ngrok.PublicUrl -PassThru

    $publicProbe = Wait-SisHttpProbe -BaseUrl $ngrok.PublicUrl -TimeoutSeconds 120
    if (-not $publicProbe.Success) {
        throw "The public URL did not reach n8n. Check ngrok and n8n logs in .runtime/logs."
    }

    Write-Host 'SIS local runtime started.'
    Write-Host ("Local editor: {0}" -f $n8n.LocalUrl)
    Write-Host ("Public webhook base: {0}" -f $ngrok.PublicUrl)
    Write-Host 'WEBHOOK_URL was supplied to the n8n child process without rewriting .env.'
    Write-Host 'A dynamic ngrok URL changes after restart; external webhook registrations and OAuth redirect configuration may need updating.'
}
catch {
    & (Join-Path $PSScriptRoot 'Stop-SIS.ps1') -Quiet
    throw
}
