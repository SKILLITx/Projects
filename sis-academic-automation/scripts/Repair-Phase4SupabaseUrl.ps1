[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvPath = Join-Path $ProjectRoot '.env'
$ExpectedUrl = 'https://ojetmpchcwfpnjbuqvuv.supabase.co'
$ExpectedHost = 'ojetmpchcwfpnjbuqvuv.supabase.co'

if (-not (Test-Path -LiteralPath $EnvPath -PathType Leaf)) {
    throw "Missing project environment file: $EnvPath"
}

$Uri = [Uri]$ExpectedUrl
if (
    $Uri.Scheme -ne 'https' -or
    $Uri.Host -ne $ExpectedHost -or
    $Uri.AbsolutePath -ne '/'
) {
    throw 'The embedded Supabase project URL failed validation.'
}

$Lines = @(Get-Content -LiteralPath $EnvPath)
$Found = $false
$Updated = foreach ($Line in $Lines) {
    if ($Line -match '^\s*SUPABASE_URL\s*=') {
        if (-not $Found) {
            $Found = $true
            "SUPABASE_URL=$ExpectedUrl"
        }
    }
    else {
        $Line
    }
}

if (-not $Found) {
    $Updated += "SUPABASE_URL=$ExpectedUrl"
}

$BackupRoot = Join-Path $ProjectRoot '.runtime\backups'
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
$BackupPath = Join-Path $BackupRoot ('.env.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak')
Copy-Item -LiteralPath $EnvPath -Destination $BackupPath -Force

[IO.File]::WriteAllLines(
    $EnvPath,
    [string[]]$Updated,
    [Text.UTF8Encoding]::new($false)
)

$SavedLine = @(
    Get-Content -LiteralPath $EnvPath |
        Where-Object { $_ -match '^\s*SUPABASE_URL\s*=' }
)

if ($SavedLine.Count -ne 1 -or $SavedLine[0] -ne "SUPABASE_URL=$ExpectedUrl") {
    throw 'SUPABASE_URL was not saved exactly once with the expected value.'
}

try {
    $Addresses = [System.Net.Dns]::GetHostAddresses($ExpectedHost)
}
catch {
    throw "DNS lookup failed for $ExpectedHost. $($_.Exception.Message)"
}

if (@($Addresses).Count -lt 1) {
    throw "DNS lookup returned no address for $ExpectedHost."
}

$Request = [System.Net.HttpWebRequest]::Create("$ExpectedUrl/rest/v1/")
$Request.Method = 'GET'
$Request.Timeout = 15000
$Request.AllowAutoRedirect = $false
$ConnectivityStatus = $null

try {
    $Response = $Request.GetResponse()
    try {
        $ConnectivityStatus = [int]$Response.StatusCode
    }
    finally {
        $Response.Close()
    }
}
catch [System.Net.WebException] {
    if ($null -eq $_.Exception.Response) {
        throw "HTTPS connection failed for $ExpectedHost. $($_.Exception.Message)"
    }

    $Response = $_.Exception.Response
    try {
        $ConnectivityStatus = [int]$Response.StatusCode
    }
    finally {
        $Response.Close()
    }
}

$RestartScript = Join-Path $PSScriptRoot 'Restart-N8nForGoogleOAuth.ps1'
if (-not (Test-Path -LiteralPath $RestartScript -PathType Leaf)) {
    throw "Missing n8n restart helper: $RestartScript"
}

& $RestartScript
if (-not $?) {
    throw 'n8n restart helper reported a failure.'
}

Write-Host 'PHASE 4 SUPABASE URL REPAIR: PASS'
Write-Host ("SUPABASE_URL: {0}" -f $ExpectedUrl)
Write-Host ("DNS addresses resolved: {0}" -f @($Addresses).Count)
Write-Host ("HTTPS connectivity status: {0}" -f $ConnectivityStatus)
Write-Host ("Environment backup: {0}" -f $BackupPath)
Write-Host 'n8n restarted while preserving the active ngrok hostname.'
