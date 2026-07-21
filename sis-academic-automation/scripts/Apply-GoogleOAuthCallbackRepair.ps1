[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TargetPath = Join-Path $PSScriptRoot 'Start-N8n.ps1'

if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
    throw "Start-N8n.ps1 was not found at $TargetPath"
}

$Text = Get-Content -LiteralPath $TargetPath -Raw -Encoding UTF8

if ($Text -match '\[string\]\$EditorBaseUrl') {
    Write-Host 'Google OAuth callback repair is already applied.'
    exit 0
}

$RuntimeDirectory = Join-Path $ProjectRoot '.runtime'
$BackupDirectory = Join-Path $RuntimeDirectory 'backups'
New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupPath = Join-Path $BackupDirectory "Start-N8n.$Timestamp.ps1"
Copy-Item -LiteralPath $TargetPath -Destination $BackupPath -Force

$OldParam = @'
param(
    [string]$WebhookUrl,
    [switch]$PassThru
)
'@

$NewParam = @'
param(
    [string]$WebhookUrl,
    [string]$EditorBaseUrl,
    [switch]$PassThru
)
'@

if (-not $Text.Contains($OldParam)) {
    throw 'The Start-N8n.ps1 parameter block did not match the expected Phase 1 runtime structure. No file was changed.'
}
$Text = $Text.Replace($OldParam, $NewParam)

$Anchor = @'
if (-not [string]::IsNullOrWhiteSpace($WebhookUrl)) {
    $normalizedWebhookUrl = $WebhookUrl.TrimEnd('/') + '/'
    [Environment]::SetEnvironmentVariable('WEBHOOK_URL', $normalizedWebhookUrl, 'Process')
    [Environment]::SetEnvironmentVariable('N8N_PROXY_HOPS', '1', 'Process')
}
'@

$Replacement = @'
if (-not [string]::IsNullOrWhiteSpace($WebhookUrl)) {
    $normalizedWebhookUrl = $WebhookUrl.TrimEnd('/') + '/'
    [Environment]::SetEnvironmentVariable('WEBHOOK_URL', $normalizedWebhookUrl, 'Process')
    [Environment]::SetEnvironmentVariable('N8N_PROXY_HOPS', '1', 'Process')
}

if (-not [string]::IsNullOrWhiteSpace($EditorBaseUrl)) {
    $normalizedEditorBaseUrl = $EditorBaseUrl.TrimEnd('/') + '/'
    [Environment]::SetEnvironmentVariable('N8N_EDITOR_BASE_URL', $normalizedEditorBaseUrl, 'Process')
}
'@

if (-not $Text.Contains($Anchor)) {
    throw 'The Start-N8n.ps1 webhook configuration block did not match the expected structure. No file was changed.'
}
$Text = $Text.Replace($Anchor, $Replacement)

[IO.File]::WriteAllText($TargetPath, $Text, [Text.UTF8Encoding]::new($true))

Write-Host 'GOOGLE OAUTH CALLBACK REPAIR: APPLIED'
Write-Host "Backup created: $BackupPath"
Write-Host 'Start-N8n.ps1 can now receive a public editor base URL without changing .env.'
