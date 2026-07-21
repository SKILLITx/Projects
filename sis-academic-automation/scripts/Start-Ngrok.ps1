[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$projectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $projectRoot | Out-Null

if ($env:SIS_PUBLIC_TUNNEL_ENABLED -eq 'false') {
    throw 'Public tunnel is disabled by SIS_PUBLIC_TUNNEL_ENABLED=false.'
}

if ($Port -le 0) {
    $Port = 5678
    if (-not [string]::IsNullOrWhiteSpace($env:N8N_PORT)) { $Port = [int]$env:N8N_PORT }
}

$runtimeDirectory = Get-SisRuntimeDirectory -ProjectRoot $projectRoot
$logDirectory = Join-Path $runtimeDirectory 'logs'
$pidDirectory = Join-Path $runtimeDirectory 'pids'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $pidDirectory -Force | Out-Null

$pidPath = Join-Path $pidDirectory 'ngrok.pid'
$existingPid = Read-SisPidFile -Path $pidPath
if ($null -ne $existingPid -and $null -ne (Get-Process -Id $existingPid -ErrorAction SilentlyContinue)) {
    throw "ngrok is already running with PID $existingPid."
}
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue

$ngrokCommand = Get-SisNgrokCommand
$arguments = @('http', ("http://127.0.0.1:{0}" -f $Port), '--log=stdout', '--log-format=json')
if (-not [string]::IsNullOrWhiteSpace($env:NGROK_DOMAIN)) {
    $arguments += ('--url=' + $env:NGROK_DOMAIN.Trim())
}

$stdoutPath = Join-Path $logDirectory 'ngrok.stdout.log'
$stderrPath = Join-Path $logDirectory 'ngrok.stderr.log'
$process = Start-Process -FilePath $ngrokCommand -ArgumentList $arguments -WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
Write-SisPidFile -Path $pidPath -ProcessId $process.Id

$apiUrl = $env:NGROK_API_URL
if ([string]::IsNullOrWhiteSpace($apiUrl)) { $apiUrl = 'http://127.0.0.1:4040/api/tunnels' }
$timeout = 120
if (-not [string]::IsNullOrWhiteSpace($env:SIS_START_TIMEOUT_SECONDS)) { $timeout = [int]$env:SIS_START_TIMEOUT_SECONDS }
$deadline = (Get-Date).AddSeconds($timeout)
$publicUrl = $null

try {
    do {
        if ($process.HasExited) { throw "ngrok exited early. Review $stderrPath" }
        try {
            $response = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 5
            $httpsTunnel = @($response.tunnels | Where-Object { $_.public_url -like 'https://*' } | Select-Object -First 1)
            if ($httpsTunnel.Count -gt 0) { $publicUrl = [string]$httpsTunnel[0].public_url }
        }
        catch { }
        if ([string]::IsNullOrWhiteSpace($publicUrl)) { Start-Sleep -Seconds 2 }
    } while ([string]::IsNullOrWhiteSpace($publicUrl) -and (Get-Date) -lt $deadline)

    if ([string]::IsNullOrWhiteSpace($publicUrl)) { throw "Could not obtain the ngrok public URL from $apiUrl." }

    $publicUrl = $publicUrl.TrimEnd('/') + '/'
    Set-Content -LiteralPath (Join-Path $runtimeDirectory 'active-webhook-url.txt') -Value $publicUrl -Encoding ASCII

    $result = [pscustomobject]@{ ProcessId = $process.Id; PublicUrl = $publicUrl; ApiUrl = $apiUrl }
    if ($PassThru) { return $result }
    Write-Host ("ngrok started. Public URL: {0}" -f $publicUrl)
}
catch {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    throw
}
