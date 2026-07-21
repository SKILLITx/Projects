[CmdletBinding()]
param(
    [switch]$AllowPortInUse,
    [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$projectRoot = Get-SisProjectRoot
$results = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail, [bool]$Required = $true)
    $results.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Required = $Required; Detail = $Detail })
}

try {
    Add-Check -Name 'PowerShell' -Passed ($PSVersionTable.PSVersion.Major -ge 5) -Detail ("Detected {0}" -f $PSVersionTable.PSVersion)

    $envLoaded = Import-SisEnvironment -ProjectRoot $projectRoot -AllowMissing
    Add-Check -Name '.env' -Passed $envLoaded -Detail $(if ($envLoaded) { 'Loaded without displaying values' } else { 'Missing; run Initialize-Environment.ps1' })

    $nodeCommand = Get-Command 'node.exe' -ErrorAction SilentlyContinue
    if ($null -eq $nodeCommand) { $nodeCommand = Get-Command 'node' -ErrorAction SilentlyContinue }
    if ($null -eq $nodeCommand) {
        Add-Check -Name 'Node.js' -Passed $false -Detail 'Not found'
    }
    else {
        $nodeText = (& $nodeCommand.Source --version 2>&1 | Out-String).Trim()
        $nodeVersion = ConvertTo-SisVersion -Text $nodeText
        Add-Check -Name 'Node.js' -Passed (Test-SisNodeVersion -Version $nodeVersion) -Detail ("Detected {0}; required >=20.19 and <25" -f $nodeVersion)
    }

    $npmCommand = Get-Command 'npm.cmd' -ErrorAction SilentlyContinue
    if ($null -eq $npmCommand) {
        Add-Check -Name 'npm' -Passed $false -Detail 'npm.cmd not found'
    }
    else {
        $npmVersion = (& $npmCommand.Source --version 2>&1 | Out-String).Trim()
        Add-Check -Name 'npm' -Passed $true -Detail ("Detected {0}" -f $npmVersion)
    }

    try {
        $n8nCommand = Get-SisN8nCommand -ProjectRoot $projectRoot
        $n8nVersionText = (& $n8nCommand --version 2>&1 | Out-String).Trim()
        $expectedText = $env:N8N_EXPECTED_VERSION
        if ([string]::IsNullOrWhiteSpace($expectedText)) { $expectedText = '2.4.0' }
        $actualVersion = ConvertTo-SisVersion -Text $n8nVersionText
        $expectedVersion = ConvertTo-SisVersion -Text $expectedText
        Add-Check -Name 'n8n exact version' -Passed ($actualVersion -eq $expectedVersion) -Detail ("Detected {0}; required {1}" -f $actualVersion, $expectedVersion)
    }
    catch { Add-Check -Name 'n8n exact version' -Passed $false -Detail $_.Exception.Message }

    try {
        $ngrokCommand = Get-SisNgrokCommand
        $ngrokVersion = (& $ngrokCommand version 2>&1 | Out-String).Trim()
        Add-Check -Name 'ngrok' -Passed $true -Detail $ngrokVersion
    }
    catch { Add-Check -Name 'ngrok' -Passed $false -Detail $_.Exception.Message }

    $port = 5678
    if (-not [string]::IsNullOrWhiteSpace($env:N8N_PORT)) { $port = [int]$env:N8N_PORT }
    $inUse = Test-SisTcpPort -Port $port
    Add-Check -Name 'n8n port' -Passed ((-not $inUse) -or $AllowPortInUse) -Detail $(if ($inUse) { "Port $port is in use" } else { "Port $port is available" })

    if ($envLoaded) {
        $key = $env:N8N_ENCRYPTION_KEY
        $keyValid = (-not [string]::IsNullOrWhiteSpace($key)) -and ($key -ne 'GENERATED_LOCALLY_BY_INITIALIZE_ENVIRONMENT') -and ($key.Length -ge 32)
        Add-Check -Name 'n8n encryption key' -Passed $keyValid -Detail $(if ($keyValid) { 'Configured; value not displayed' } else { 'Missing or placeholder' })

        $userFolderValue = $env:N8N_USER_FOLDER
        if ([string]::IsNullOrWhiteSpace($userFolderValue)) { $userFolderValue = '.runtime/n8n-user' }
        $userFolder = Resolve-SisPath -ProjectRoot $projectRoot -Value $userFolderValue
        $userFolderExists = Test-Path -LiteralPath $userFolder -PathType Container
        Add-Check -Name 'n8n user folder' -Passed $userFolderExists -Detail $userFolder
    }
}
catch {
    Add-Check -Name 'validator' -Passed $false -Detail $_.Exception.Message
}

$failedRequired = @($results | Where-Object { $_.Required -and -not $_.Passed })
$summary = [pscustomobject]@{
    Success = ($failedRequired.Count -eq 0)
    ProjectRoot = $projectRoot
    Checks = $results
}

if ($Json) {
    $summary | ConvertTo-Json -Depth 5
}
else {
    foreach ($item in $results) {
        $label = if ($item.Passed) { 'PASS' } else { 'FAIL' }
        Write-Host ("[{0}] {1}: {2}" -f $label, $item.Name, $item.Detail)
    }
    if ($summary.Success) { Write-Host 'Environment validation passed.' }
    else { Write-Host 'Environment validation failed.' }
}

if (-not $summary.Success) { exit 1 }
