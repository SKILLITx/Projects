[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvPath = Join-Path $ProjectRoot '.env'
if (-not (Test-Path -LiteralPath $EnvPath -PathType Leaf)) {
  throw '.env is missing. Run scripts\Initialize-Environment.ps1 first.'
}

function Read-RequiredValue([string]$Prompt, [string]$Pattern) {
  $Value = (Read-Host $Prompt).Trim()
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch $Pattern) {
    throw "Invalid value for $Prompt"
  }
  return $Value
}

$Values = [ordered]@{
  SIS_STUDENT_PROFILE_RESPONSE_SHEET_ID = Read-RequiredValue 'Student-profile response Spreadsheet ID' '^[A-Za-z0-9_-]{10,}$'
  SIS_STUDENT_PROFILE_QUEUE_TAB_ID = Read-RequiredValue 'Student-profile Automation Queue tab ID (gid)' '^\d+$'
  SIS_ENROLLMENT_RESPONSE_SHEET_ID = Read-RequiredValue 'Enrollment response Spreadsheet ID' '^[A-Za-z0-9_-]{10,}$'
  SIS_ENROLLMENT_QUEUE_TAB_ID = Read-RequiredValue 'Enrollment Automation Queue tab ID (gid)' '^\d+$'
  SIS_NOTIFICATION_BATCH_SIZE = Read-RequiredValue 'Notification batch size [1-100]' '^(?:[1-9]|[1-9]\d|100)$'
}

$Lines = Get-Content -LiteralPath $EnvPath
foreach ($Key in $Values.Keys) {
  $Replacement = "$Key=$($Values[$Key])"
  $Found = $false
  for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
    if ($Lines[$Index] -match ('^' + [Regex]::Escape($Key) + '=')) {
      $Lines[$Index] = $Replacement
      $Found = $true
      break
    }
  }
  if (-not $Found) { $Lines += $Replacement }
}

[IO.File]::WriteAllLines($EnvPath, $Lines, [Text.UTF8Encoding]::new($false))
Write-Host 'Phase 4 Wave 1 non-secret Google IDs and batch settings were written to .env.'
