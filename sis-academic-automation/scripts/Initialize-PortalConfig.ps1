[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PortalDir = Join-Path $ProjectRoot 'portal'
$ConfigPath = Join-Path $PortalDir 'config.local.js'

function Resolve-SupabaseProjectUrl {
  param(
    [AllowNull()]
    [string]$InputValue,
    [Parameter(Mandatory = $true)]
    [string]$DefaultUrl
  )

  $Value = if ($null -eq $InputValue) { '' } else { $InputValue.Trim() }
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $DefaultUrl
  }

  # Accept a bare project reference.
  if ($Value -match '^[a-z0-9]{20}$') {
    return "https://$Value.supabase.co"
  }

  # Accept a Supabase dashboard project URL and extract its project reference.
  if ($Value -match '^https://supabase\.com/dashboard/project/(?<ref>[a-z0-9]{20})(?:/.*)?$') {
    return "https://$($Matches['ref']).supabase.co"
  }

  # Accept the normal project API URL, with optional surrounding whitespace,
  # trailing slash, or copied path/query fragments.
  if ($Value -match '^https://(?<ref>[a-z0-9]{20})\.supabase\.co(?:[/?#].*)?$') {
    return "https://$($Matches['ref']).supabase.co"
  }

  throw @'
Supabase URL format is invalid.

Accepted examples:
  https://ojetmpchcwfpnjbuqvuv.supabase.co
  ojetmpchcwfpnjbuqvuv
  https://supabase.com/dashboard/project/ojetmpchcwfpnjbuqvuv
'@
}

$DefaultUrl = 'https://ojetmpchcwfpnjbuqvuv.supabase.co'
$RawUrl = Read-Host "Supabase URL or project reference [$DefaultUrl]"
$SupabaseUrl = Resolve-SupabaseProjectUrl -InputValue $RawUrl -DefaultUrl $DefaultUrl

$AnonSecure = Read-Host 'Supabase publishable/anon key (entered locally and never printed)' -AsSecureString
$Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AnonSecure)
try {
  $AnonKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
}
finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
}

if ([string]::IsNullOrWhiteSpace($AnonKey) -or $AnonKey.Length -lt 20) {
  throw 'Supabase publishable/anon key was not provided or is too short.'
}

if ($AnonKey -match '^sb_secret_' -or $AnonKey -match 'service_role') {
  throw 'A Supabase secret/service-role key must not be placed in browser configuration. Use the publishable/anon key.'
}

$EscapedUrl = $SupabaseUrl.Replace('\','\\').Replace('"','\"')
$EscapedKey = $AnonKey.Replace('\','\\').Replace('"','\"')
$Content = @"
window.SIS_PORTAL_CONFIG = {
  supabaseUrl: "$EscapedUrl",
  supabaseAnonKey: "$EscapedKey",
  portalMode: "direct-rpc",
  n8nBaseUrl: "",
  requestTimeoutMs: 30000
};
"@

[IO.File]::WriteAllText($ConfigPath, $Content, [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'Update-GitignorePhase3.ps1')
Write-Host "Portal configuration written for $SupabaseUrl without displaying the key."
