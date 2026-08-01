[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$GooglePath = Join-Path $ProjectRoot 'evidence\phase-3-google-workspace-verification.json'
$AuthPath = Join-Path $ProjectRoot 'evidence\phase-3-authorization-verification.json'

foreach ($Path in @($GooglePath, $AuthPath)) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing Phase 3 completion evidence: $Path"
  }
}

$Google = Get-Content -LiteralPath $GooglePath -Raw | ConvertFrom-Json
$Auth = Get-Content -LiteralPath $AuthPath -Raw | ConvertFrom-Json

if (-not $Google.success) { throw 'Google Workspace verification did not pass.' }
if ($Google.forms -ne 6) { throw 'Expected six Google Forms.' }
if ($Google.response_spreadsheets -ne 6) { throw 'Expected six linked response spreadsheets.' }
if ($Google.form_submit_triggers -ne 6) { throw 'Expected six form-submit triggers.' }
if ($Google.folders -ne 12) { throw 'Expected twelve Drive folders.' }
if (@($Google.missing).Count -ne 0) { throw 'Google Workspace verification reported missing assets.' }

if (-not $Auth.success) { throw 'Authorization verification did not pass.' }
if (-not $Auth.dashboard_rpc_success) { throw 'Authenticated dashboard RPC verification did not pass.' }
if ($Auth.institutions_visible -lt 2) { throw 'Super administrator did not see both institutions.' }
if ($Auth.campuses_visible -lt 4) { throw 'Super administrator did not see all four campuses.' }

$RequiredPortalFiles = @(
  'portal\index.html',
  'portal\app.js',
  'portal\styles.css',
  'portal\config.example.js'
)
foreach ($RelativePath in $RequiredPortalFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $RelativePath) -PathType Leaf)) {
    throw "Missing staff portal file: $RelativePath"
  }
}

Write-Host 'PHASE 3 COMPLETION CHECK: PASS'
Write-Host 'Google Workspace, staff authentication, authorization scope and dashboard RPC are verified.'
Write-Host 'Phase 4 workflow implementation may begin.'
