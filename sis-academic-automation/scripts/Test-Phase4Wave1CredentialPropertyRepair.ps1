[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$RecoveryPath = Join-Path $PSScriptRoot 'Recover-Phase4Wave1CodeContractRepair.ps1'
if (-not (Test-Path -LiteralPath $RecoveryPath -PathType Leaf)) {
    throw "Missing recovery script: $RecoveryPath"
}

$Text = Get-Content -LiteralPath $RecoveryPath -Raw

foreach ($Required in @(
    "PSObject.Properties['credentials']",
    '$CredentialProperty.Value',
    '$AfterCredentialProperty.Value',
    'Credential binding disappeared during recovery'
)) {
    if (-not $Text.Contains($Required)) {
        throw "Credential-property repair validation failed: missing $Required"
    }
}

foreach ($Forbidden in @(
    '$Node.credentials',
    '$AfterNode[0].credentials'
)) {
    if ($Text.Contains($Forbidden)) {
        throw "Strict-mode-unsafe credential access remains: $Forbidden"
    }
}

$SampleNodeWithoutCredentials = [PSCustomObject]@{
    name = 'Code node without credentials'
    type = 'n8n-nodes-base.code'
}

$CredentialProperty = $SampleNodeWithoutCredentials.PSObject.Properties['credentials']
if ($null -ne $CredentialProperty) {
    throw 'Optional-property regression fixture unexpectedly contained credentials.'
}

$SampleNodeWithCredentials = [PSCustomObject]@{
    name = 'HTTP node'
    credentials = [PSCustomObject]@{
        supabaseApi = [PSCustomObject]@{
            id = 'fixture-id'
            name = 'fixture-name'
        }
    }
}

$CredentialProperty = $SampleNodeWithCredentials.PSObject.Properties['credentials']
if ($null -eq $CredentialProperty -or $null -eq $CredentialProperty.Value) {
    throw 'Credential-property regression fixture could not read an existing property.'
}

Write-Host 'PHASE 4 WAVE 1 CREDENTIAL PROPERTY REPAIR: PASS'
Write-Host 'Verified StrictMode-safe handling for nodes with and without credential properties.'
