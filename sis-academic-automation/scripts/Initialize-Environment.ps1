[CmdletBinding()]
param([switch]$Force)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$projectRoot = Get-SisProjectRoot
$examplePath = Join-Path $projectRoot '.env.example'
$envPath = Join-Path $projectRoot '.env'

if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) {
    throw "Missing .env.example at $examplePath"
}

if ((Test-Path -LiteralPath $envPath -PathType Leaf) -and -not $Force) {
    throw ".env already exists. Use -Force only when you intentionally want to replace it."
}

$content = Get-Content -LiteralPath $examplePath -Raw -Encoding UTF8
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
$bytes = New-Object byte[] 32
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$encryptionKey = [Convert]::ToBase64String($bytes)
$content = $content.Replace('N8N_ENCRYPTION_KEY=GENERATED_LOCALLY_BY_INITIALIZE_ENVIRONMENT', 'N8N_ENCRYPTION_KEY=' + $encryptionKey)

[System.IO.File]::WriteAllText($envPath, $content, (New-Object System.Text.UTF8Encoding($false)))

[Environment]::SetEnvironmentVariable('SIS_RUNTIME_DIR', '.runtime', 'Process')
$runtimeDirectory = Get-SisRuntimeDirectory -ProjectRoot $projectRoot
$directories = @(
    $runtimeDirectory,
    (Join-Path $runtimeDirectory 'logs'),
    (Join-Path $runtimeDirectory 'pids'),
    (Join-Path $runtimeDirectory 'n8n-user')
)
foreach ($directory in $directories) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

Write-Host 'Environment initialized.'
Write-Host 'Created .env with a locally generated n8n encryption key. The key was not printed.'
Write-Host 'Created .runtime directories.'
