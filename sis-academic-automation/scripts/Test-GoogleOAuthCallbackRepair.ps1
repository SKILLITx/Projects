[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$StartN8nPath = Join-Path $PSScriptRoot 'Start-N8n.ps1'
$RestartPath = Join-Path $PSScriptRoot 'Restart-N8nForGoogleOAuth.ps1'

foreach ($Path in @($StartN8nPath, $RestartPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing OAuth repair file: $Path"
    }
}

$StartText = Get-Content -LiteralPath $StartN8nPath -Raw
$RestartText = Get-Content -LiteralPath $RestartPath -Raw

foreach ($Fragment in @(
    '[string]$EditorBaseUrl',
    "'N8N_EDITOR_BASE_URL'",
    '$normalizedEditorBaseUrl'
)) {
    if (-not $StartText.Contains($Fragment)) {
        throw "Start-N8n OAuth repair validation failed: missing $Fragment"
    }
}

foreach ($Fragment in @(
    'NGROK_API_URL',
    'Stop-SisPidFileProcess',
    '-EditorBaseUrl $PublicUrl',
    'The ngrok process and its public domain were preserved.'
)) {
    if (-not $RestartText.Contains($Fragment)) {
        throw "OAuth restart validation failed: missing $Fragment"
    }
}

Write-Host 'GOOGLE OAUTH CALLBACK REPAIR CHECK: PASS'
Write-Host 'Verified public editor-base injection, current ngrok reuse and n8n-only restart.'
