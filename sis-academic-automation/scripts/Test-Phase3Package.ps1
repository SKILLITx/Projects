[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$RequiredFiles = @(
  'google\forms\form-specifications.json',
  'google\forms\form-field-catalog.csv',
  'google\sheets\response-sheet-contract.json',
  'google\drive\folder-plan.json',
  'google\provisioning\SIS-WorkspaceProvisioner.gs',
  'google\provisioning\appsscript.json',
  'google\templates\transcript-template-guide.md',
  'google\templates\hec-template-guide.md',
  'google\templates\dashboard-template-guide.md',
  'portal\index.html',
  'portal\styles.css',
  'portal\app.js',
  'portal\config.example.js',
  'docs\testing\phase3-authorization-test-guide.md',
  'docs\testing\phase3-authorization-test-matrix.csv'
)

foreach ($RelativePath in $RequiredFiles) {
  $FullPath = Join-Path $ProjectRoot $RelativePath
  if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
    throw "Missing required Phase 3 file: $RelativePath"
  }
}

$FormSpec = Get-Content -LiteralPath (Join-Path $ProjectRoot 'google\forms\form-specifications.json') -Raw | ConvertFrom-Json
if (@($FormSpec.forms).Count -ne 6) {
  throw 'Phase 3 must contain exactly six Google Form specifications.'
}

$FolderPlan = Get-Content -LiteralPath (Join-Path $ProjectRoot 'google\drive\folder-plan.json') -Raw | ConvertFrom-Json
if (@($FolderPlan.folders).Count -lt 6) {
  throw 'The Drive folder plan is incomplete.'
}

$ResponseContract = Get-Content -LiteralPath (Join-Path $ProjectRoot 'google\sheets\response-sheet-contract.json') -Raw | ConvertFrom-Json
if (@($ResponseContract.automation_queue_columns).Count -lt 12) {
  throw 'The Automation Queue contract is incomplete.'
}

function Test-IsAllowedPlaceholder {
  param([AllowNull()][string]$Value)

  if ($null -eq $Value) { return $true }

  $Normalized = $Value.Trim()
  if ($Normalized.Length -ge 2) {
    if (
      ($Normalized.StartsWith('"') -and $Normalized.EndsWith('"')) -or
      ($Normalized.StartsWith("'") -and $Normalized.EndsWith("'"))
    ) {
      $Normalized = $Normalized.Substring(1, $Normalized.Length - 2).Trim()
    }
  }

  if ([string]::IsNullOrWhiteSpace($Normalized)) { return $true }
  if ($Normalized -match '^<[^>]+>$') { return $true }

  return $Normalized -match '^(REPLACE|YOUR|GENERATED|SET|EXAMPLE|PLACEHOLDER|NOT_SET|EMPTY|INSERT|ADD|CONFIGURE)[A-Z0-9_.:/<>\-]*$'
}

$SecretVariableNames = @(
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_SECRET_KEY',
  'SUPABASE_SECRET_KEYS',
  'N8N_ENCRYPTION_KEY',
  'NGROK_AUTHTOKEN',
  'GOOGLE_CLIENT_SECRET',
  'GOOGLE_OAUTH_CLIENT_SECRET'
)

$AssignmentPattern = '^\s*(?<name>' + (($SecretVariableNames | ForEach-Object { [Regex]::Escape($_) }) -join '|') + ')\s*=\s*(?<value>.*?)\s*$'
$PortableSecretPatterns = @(
  'sb_secret_[A-Za-z0-9_\-]{16,}',
  'AIza[0-9A-Za-z\-_]{20,}',
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
)

$LocalOnlyFiles = @(
  [IO.Path]::GetFullPath((Join-Path $ProjectRoot '.env')),
  [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'portal\config.local.js'))
)

$ScanFiles = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File | Where-Object {
  $FullPath = [IO.Path]::GetFullPath($_.FullName)
  $IgnoredDirectory = $FullPath -match '[\\/](node_modules|\.runtime|\.git)[\\/]'
  $LocalOnlyFile = $LocalOnlyFiles -contains $FullPath
  (-not $IgnoredDirectory) -and (-not $LocalOnlyFile)
}

foreach ($File in $ScanFiles) {
  $Text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $Text) { continue }

  foreach ($Pattern in $PortableSecretPatterns) {
    if ($Text -match $Pattern) {
      throw "Potential secret detected in portable project file: $($File.FullName)"
    }
  }

  foreach ($Line in ($Text -split "`r?`n")) {
    if ($Line -match $AssignmentPattern) {
      $VariableName = $Matches['name']
      $AssignedValue = $Matches['value']

      if (-not (Test-IsAllowedPlaceholder -Value $AssignedValue)) {
        throw "Potential secret assigned to $VariableName in portable project file: $($File.FullName)"
      }
    }
  }
}

Write-Host 'PHASE 3 PACKAGE STATIC CHECK: PASS'
Write-Host 'Verified 6 form specifications, Google asset provisioner, staff portal and authorization test package.'
