[CmdletBinding()]
param(
  [string]$Repository = "D:\AI automation\zaid278-workflows\skill it\Project 1\V2\sis-academic-automation"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Repository)) { throw "Repository not found: $Repository" }
$paths = @(
  (Join-Path $Repository 'database\queries\workflow10-schema-inspection.sql'),
  (Join-Path $Repository 'database\queries\workflow10-rpc-inspection.sql'),
  (Join-Path $Repository 'database\queries\workflow10-operational-snapshot.sql')
)
foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path)) { throw "Preflight SQL file not found: $path" } }
$content = ($paths | ForEach-Object { "`r`n-- FILE: $_`r`n" + (Get-Content -LiteralPath $_ -Raw) }) -join "`r`n"
$content | Set-Clipboard
Write-Host 'SIS 10 READ-ONLY PREFLIGHT SQL: COPIED'
Write-Host 'Run it in Supabase SQL Editor. It returns three compact JSON rows and performs no writes.'
