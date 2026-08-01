[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Gitignore = Join-Path $ProjectRoot '.gitignore'
$RequiredLines = @(
  'portal/config.local.js',
  '.runtime/phase3/',
  '.runtime/portal/'
)

if (-not (Test-Path -LiteralPath $Gitignore)) {
  [IO.File]::WriteAllText($Gitignore, '', [Text.UTF8Encoding]::new($false))
}

$Existing = Get-Content -LiteralPath $Gitignore -ErrorAction SilentlyContinue
$ToAppend = @()
foreach ($Line in $RequiredLines) {
  if ($Existing -notcontains $Line) { $ToAppend += $Line }
}

if ($ToAppend.Count -gt 0) {
  Add-Content -LiteralPath $Gitignore -Value ("`r`n# Phase 3 local-only files`r`n" + ($ToAppend -join "`r`n"))
}
