[CmdletBinding()]
param(
    [string]$WebhookUrl,
    [string]$EditorBaseUrl,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$projectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $projectRoot | Out-Null

if (-not [string]::IsNullOrWhiteSpace($WebhookUrl)) {
    $normalizedWebhookUrl = $WebhookUrl.TrimEnd('/') + '/'
    [Environment]::SetEnvironmentVariable('WEBHOOK_URL', $normalizedWebhookUrl, 'Process')
    [Environment]::SetEnvironmentVariable('N8N_PROXY_HOPS', '1', 'Process')
}

if (-not [string]::IsNullOrWhiteSpace($EditorBaseUrl)) {
    $normalizedEditorBaseUrl = $EditorBaseUrl.TrimEnd('/') + '/'
    [Environment]::SetEnvironmentVariable('N8N_EDITOR_BASE_URL', $normalizedEditorBaseUrl, 'Process')
}

$userFolderValue = $env:N8N_USER_FOLDER
if ([string]::IsNullOrWhiteSpace($userFolderValue)) { $userFolderValue = '.runtime/n8n-user' }
$userFolder = Resolve-SisPath -ProjectRoot $projectRoot -Value $userFolderValue
New-Item -ItemType Directory -Path $userFolder -Force | Out-Null
[Environment]::SetEnvironmentVariable('N8N_USER_FOLDER', $userFolder, 'Process')

$port = 5678
if (-not [string]::IsNullOrWhiteSpace($env:N8N_PORT)) { $port = [int]$env:N8N_PORT }
if (Test-SisTcpPort -Port $port) { throw "Port $port is already in use." }

$n8nCommand = Get-SisN8nCommand -ProjectRoot $projectRoot
$versionText = (& $n8nCommand --version 2>&1 | Out-String).Trim()
$actualVersion = ConvertTo-SisVersion -Text $versionText
$expectedText = $env:N8N_EXPECTED_VERSION
if ([string]::IsNullOrWhiteSpace($expectedText)) { $expectedText = '2.4.0' }
$expectedVersion = ConvertTo-SisVersion -Text $expectedText
if ($actualVersion -ne $expectedVersion) {
    throw "n8n version mismatch. Detected $actualVersion; required $expectedVersion."
}

$runtimeDirectory = Get-SisRuntimeDirectory -ProjectRoot $projectRoot
$logDirectory = Join-Path $runtimeDirectory 'logs'
$pidDirectory = Join-Path $runtimeDirectory 'pids'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $pidDirectory -Force | Out-Null

$pidPath = Join-Path $pidDirectory 'n8n.pid'
$existingPid = Read-SisPidFile -Path $pidPath
if ($null -ne $existingPid -and $null -ne (Get-Process -Id $existingPid -ErrorAction SilentlyContinue)) {
    throw "n8n is already running with PID $existingPid."
}
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue

$stdoutPath = Join-Path $logDirectory 'n8n.stdout.log'
$stderrPath = Join-Path $logDirectory 'n8n.stderr.log'
$quotedCommand = '""{0}" start"' -f $n8nCommand
$process = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/s', '/c', $quotedCommand) -WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
Write-SisPidFile -Path $pidPath -ProcessId $process.Id

$localBaseUrl = "http://127.0.0.1:$port"
$timeout = 120
if (-not [string]::IsNullOrWhiteSpace($env:SIS_START_TIMEOUT_SECONDS)) { $timeout = [int]$env:SIS_START_TIMEOUT_SECONDS }
$result = Wait-SisHttpProbe -BaseUrl $localBaseUrl -TimeoutSeconds $timeout
if (-not $result.Success) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    throw "n8n did not become healthy. Review $stderrPath and $stdoutPath"
}

$output = [pscustomobject]@{ ProcessId = $process.Id; LocalUrl = ($localBaseUrl + '/'); ProbeUrl = $result.Url; Version = [string]$actualVersion }
if ($PassThru) { return $output }
Write-Host ("n8n {0} started at {1}" -f $actualVersion, $output.LocalUrl)
