$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectRoot
$coreListening = @(Get-NetTCPConnection -LocalPort 5678 -State Listen -ErrorAction SilentlyContinue).Count -gt 0
if (-not $coreListening) {
  & (Join-Path $PSScriptRoot 'Start-SIS.ps1')
} else {
  Write-Host 'SIS core runtime is already running on port 5678.'
}
$portalListening = @(Get-NetTCPConnection -LocalPort 4173 -State Listen -ErrorAction SilentlyContinue).Count -gt 0
if (-not $portalListening) {
  $portalScript = Join-Path $PSScriptRoot 'Start-Portal.ps1'
  $portalCommand = "Set-Location -LiteralPath '$ProjectRoot'; & '$portalScript'"
  Start-Process powershell.exe -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-Command',$portalCommand) | Out-Null
} else {
  Write-Host 'SIS portal is already running on port 4173.'
}
$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
  Start-Sleep -Seconds 1
  try {
    $n8n = Invoke-WebRequest -Uri 'http://127.0.0.1:5678/' -UseBasicParsing -TimeoutSec 2
    $portal = Invoke-WebRequest -Uri 'http://127.0.0.1:4173/' -UseBasicParsing -TimeoutSec 2
    $transcript = Invoke-WebRequest -Uri 'http://127.0.0.1:4173/transcript-pilot.html' -UseBasicParsing -TimeoutSec 2
    if ($n8n.StatusCode -eq 200 -and $portal.StatusCode -eq 200 -and $transcript.StatusCode -eq 200) { $ready = $true; break }
  } catch {}
}
if (-not $ready) { throw 'One or more SIS services did not become reachable within 30 seconds.' }
Write-Host 'SIS COMPLETE STARTUP: PASS'
Write-Host 'n8n: http://127.0.0.1:5678/'
Write-Host 'Staff portal: http://127.0.0.1:4173/'
Write-Host 'Transcript portal: http://127.0.0.1:4173/transcript-pilot.html'
