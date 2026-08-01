[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $ProjectRoot 'portal\config.local.js'
$EnvPath = Join-Path $ProjectRoot '.env'

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Host 'SIS 04 PORTAL WEBHOOK MODE: SKIPPED'
    Write-Host 'portal\config.local.js does not exist yet.'
    exit 0
}

$WebhookUrl = ''
if (Test-Path -LiteralPath $EnvPath -PathType Leaf) {
    foreach ($Line in Get-Content -LiteralPath $EnvPath) {
        if ($Line -match '^\s*WEBHOOK_URL\s*=\s*(.+?)\s*$') {
            $WebhookUrl = $Matches[1].Trim().Trim('"').Trim("'").TrimEnd('/')
            break
        }
    }
}

$Content = Get-Content -LiteralPath $ConfigPath -Raw
$Content = [regex]::Replace(
    $Content,
    'portalMode\s*:\s*"[^"]*"',
    'portalMode: "n8n-authenticated-webhook"'
)

if ($WebhookUrl) {
    $Escaped = $WebhookUrl.Replace('\', '\\').Replace('"', '\"')
    $Content = [regex]::Replace(
        $Content,
        'n8nBaseUrl\s*:\s*"[^"]*"',
        ('n8nBaseUrl: "' + $Escaped + '"')
    )
}

$Utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ConfigPath, $Content, $Utf8)

Write-Host 'SIS 04 PORTAL WEBHOOK MODE: CONFIGURED'
if (-not $WebhookUrl) {
    Write-Host 'Set n8nBaseUrl in portal\config.local.js before using the portal.'
}
