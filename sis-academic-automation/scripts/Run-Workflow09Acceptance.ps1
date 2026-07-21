[CmdletBinding()]
param(
    [string]$StaffEmail = 'zaidrizwan.278@gmail.com',
    [switch]$SkipLiveRunCheck
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestPath = Join-Path $ProjectRoot 'tests\acceptance\workflow09-operations-monitoring.acceptance.mjs'
$ConfigPath = Join-Path $ProjectRoot 'portal\config.local.js'
if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) { throw "Workflow 09 acceptance test was not found: $TestPath" }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "portal\config.local.js was not found. Restore the existing local portal configuration first." }

$SecurePassword = Read-Host "Supabase password for $StaffEmail" -AsSecureString
$Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
try {
    $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
    $env:S09_STAFF_EMAIL = $StaffEmail
    $env:S09_STAFF_PASSWORD = $PlainPassword
    $env:S09_REQUIRE_LIVE = if ($SkipLiveRunCheck) { 'false' } else { 'true' }
    & node $TestPath
    if ($LASTEXITCODE -ne 0) { throw "Workflow 09 acceptance suite failed with exit code $LASTEXITCODE." }
}
finally {
    Remove-Item Env:S09_STAFF_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:S09_STAFF_EMAIL -ErrorAction SilentlyContinue
    Remove-Item Env:S09_REQUIRE_LIVE -ErrorAction SilentlyContinue
    if ($null -ne $Pointer) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer) }
    $PlainPassword = $null
    $SecurePassword = $null
}
Write-Host 'SIS 09 ACCEPTANCE: PASS'
