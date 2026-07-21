[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Config = Join-Path $ProjectRoot 'portal\config.local.js'
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
  throw 'portal\config.local.js is missing. Run scripts\Initialize-PortalConfig.ps1 first.'
}

Push-Location -LiteralPath $ProjectRoot
try {
  node '.\scripts\serve-portal.js'
} finally {
  Pop-Location
}
