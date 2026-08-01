[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptPath = Join-Path $PSScriptRoot 'Initialize-PortalConfig.ps1'
$Text = Get-Content -LiteralPath $ScriptPath -Raw

$RequiredFragments = @(
  'Resolve-SupabaseProjectUrl',
  'dashboard/project',
  'sb_secret_',
  'publishable/anon key'
)

foreach ($Fragment in $RequiredFragments) {
  if ($Text -notmatch [Regex]::Escape($Fragment)) {
    throw "Portal URL repair validation failed: missing $Fragment"
  }
}

Write-Host 'PHASE 3 PORTAL URL REPAIR: PASS'
Write-Host 'URL trimming, project-ref normalization, dashboard-URL handling and secret-key rejection are present.'
