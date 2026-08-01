[CmdletBinding()]
param(
    [ValidateSet('Positive','Negative','All')]
    [string]$Mode = 'All',
    [string]$StaffEmail = 'zaidrizwan.278@gmail.com'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestPath = Join-Path $ProjectRoot 'tests\acceptance\workflow07-admin-dashboard.acceptance.mjs'
$ConfigPath = Join-Path $ProjectRoot 'portal\config.local.js'
if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) { throw "Workflow 07 acceptance test was not found: $TestPath" }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "portal\config.local.js was not found. Initialize the local portal configuration first." }

$SecurePassword = Read-Host "Supabase password for $StaffEmail" -AsSecureString
$Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
try {
    $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
    $env:S07_STAFF_EMAIL = $StaffEmail
    $env:S07_STAFF_PASSWORD = $PlainPassword
    & node $TestPath "--mode=$($Mode.ToLowerInvariant())"
    if ($LASTEXITCODE -ne 0) { throw "Workflow 07 $Mode acceptance suite failed with exit code $LASTEXITCODE." }
}
finally {
    Remove-Item Env:S07_STAFF_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:S07_STAFF_EMAIL -ErrorAction SilentlyContinue
    if ($null -ne $Pointer) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer) }
    $PlainPassword = $null
    $SecurePassword = $null
}

Write-Host "SIS 07 $($Mode.ToUpperInvariant()) ACCEPTANCE: PASS"
