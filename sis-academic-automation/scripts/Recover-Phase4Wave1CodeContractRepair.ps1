[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$ProjectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $ProjectRoot | Out-Null

$N8nCli = Join-Path $ProjectRoot 'node_modules\.bin\n8n.cmd'
$StartN8n = Join-Path $PSScriptRoot 'Start-N8n.ps1'
$SourcePath = Join-Path $ProjectRoot 'workflows\08-notification-dispatcher.json'
$WorkflowId = '3b0adf1b-93eb-51df-872a-76485036e76b'

foreach ($Path in @($N8nCli, $StartN8n, $SourcePath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required recovery file is missing: $Path"
    }
}

$ApiUrl = $env:NGROK_API_URL
if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    $ApiUrl = 'http://127.0.0.1:4040/api/tunnels'
}

try {
    $NgrokStatus = Invoke-RestMethod -Uri $ApiUrl -Method Get -TimeoutSec 10
}
catch {
    throw 'The current ngrok tunnel could not be read. Keep ngrok running before applying this recovery.'
}

$HttpsTunnel = @($NgrokStatus.tunnels) |
    Where-Object { $_.public_url -like 'https://*' } |
    Select-Object -First 1

if ($null -eq $HttpsTunnel) {
    throw 'No active HTTPS ngrok tunnel was found.'
}

$PublicUrl = ([string]$HttpsTunnel.public_url).TrimEnd('/')
$RuntimeDirectory = Get-SisRuntimeDirectory -ProjectRoot $ProjectRoot
$N8nPidPath = Join-Path $RuntimeDirectory 'pids\n8n.pid'
$RecoveryRoot = Join-Path $RuntimeDirectory ('repairs\phase4-wave1-code-recovery-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $RecoveryRoot -Force | Out-Null

$BeforePath = Join-Path $RecoveryRoot "$WorkflowId.before.json"
$PatchedPath = Join-Path $RecoveryRoot "$WorkflowId.patched.json"
$AfterPath = Join-Path $RecoveryRoot "$WorkflowId.after.json"

$Stopped = Stop-SisPidFileProcess -Path $N8nPidPath
Start-Sleep -Seconds 2

$Failure = $null

try {
    Push-Location $ProjectRoot
    try {
        & $N8nCli export:workflow "--id=$WorkflowId" "--output=$BeforePath" --pretty
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $BeforePath)) {
            throw 'Could not export the live notification workflow.'
        }

        $ParsedLive = Get-Content -LiteralPath $BeforePath -Raw | ConvertFrom-Json
        $LiveWorkflow = if ($ParsedLive -is [System.Array]) { $ParsedLive[0] } else { $ParsedLive }
        $SourceWorkflow = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json

        $CredentialSnapshot = @{}
        foreach ($Node in @($LiveWorkflow.nodes)) {
            $CredentialProperty = $Node.PSObject.Properties['credentials']
            if ($null -ne $CredentialProperty -and $null -ne $CredentialProperty.Value) {
                $CredentialSnapshot[[string]$Node.name] = ConvertTo-Json `
                    $CredentialProperty.Value `
                    -Depth 20 `
                    -Compress
            }
        }

        $SourceCodeNodes = @(
            $SourceWorkflow.nodes |
                Where-Object { $_.type -eq 'n8n-nodes-base.code' }
        )

        if ($SourceCodeNodes.Count -ne 5) {
            throw "Expected five Code nodes in Workflow 08, found $($SourceCodeNodes.Count)."
        }

        foreach ($SourceNode in $SourceCodeNodes) {
            $Matches = @(
                $LiveWorkflow.nodes |
                    Where-Object {
                        $_.type -eq 'n8n-nodes-base.code' -and
                        $_.name -eq $SourceNode.name
                    }
            )

            if ($Matches.Count -ne 1) {
                throw "Could not uniquely locate live Code node '$($SourceNode.name)'."
            }

            $LiveParameters = $Matches[0].parameters
            $SourceMode = [string]$SourceNode.parameters.mode
            $SourceCode = [string]$SourceNode.parameters.jsCode

            $ModeProperty = $LiveParameters.PSObject.Properties['mode']
            if ($null -eq $ModeProperty) {
                $LiveParameters | Add-Member -MemberType NoteProperty -Name 'mode' -Value $SourceMode
            }
            else {
                $ModeProperty.Value = $SourceMode
            }

            $CodeProperty = $LiveParameters.PSObject.Properties['jsCode']
            if ($null -eq $CodeProperty) {
                $LiveParameters | Add-Member -MemberType NoteProperty -Name 'jsCode' -Value $SourceCode
            }
            else {
                $CodeProperty.Value = $SourceCode
            }
        }

        $Json = ConvertTo-Json -InputObject @($LiveWorkflow) -Depth 100
        [IO.File]::WriteAllText($PatchedPath, $Json, [Text.UTF8Encoding]::new($false))

        & $N8nCli import:workflow "--input=$PatchedPath" --activeState=false
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not import the recovered notification workflow.'
        }

        & $N8nCli export:workflow "--id=$WorkflowId" "--output=$AfterPath" --pretty
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $AfterPath)) {
            throw 'Could not export the recovered workflow for verification.'
        }

        $ParsedAfter = Get-Content -LiteralPath $AfterPath -Raw | ConvertFrom-Json
        $AfterWorkflow = if ($ParsedAfter -is [System.Array]) { $ParsedAfter[0] } else { $ParsedAfter }

        foreach ($SourceNode in $SourceCodeNodes) {
            $AfterNode = @(
                $AfterWorkflow.nodes |
                    Where-Object {
                        $_.type -eq 'n8n-nodes-base.code' -and
                        $_.name -eq $SourceNode.name
                    }
            )

            if ($AfterNode.Count -ne 1) {
                throw "Recovered export is missing Code node '$($SourceNode.name)'."
            }

            if ([string]$AfterNode[0].parameters.mode -ne [string]$SourceNode.parameters.mode) {
                throw "Recovered mode mismatch for '$($SourceNode.name)'."
            }

            if ([string]$AfterNode[0].parameters.jsCode -ne [string]$SourceNode.parameters.jsCode) {
                throw "Recovered JavaScript mismatch for '$($SourceNode.name)'."
            }
        }

        foreach ($NodeName in $CredentialSnapshot.Keys) {
            $AfterNode = @($AfterWorkflow.nodes | Where-Object { $_.name -eq $NodeName })
            if ($AfterNode.Count -ne 1) {
                throw "Credential-bearing node disappeared after recovery: $NodeName"
            }

            $AfterCredentialProperty = $AfterNode[0].PSObject.Properties['credentials']
            if ($null -eq $AfterCredentialProperty -or $null -eq $AfterCredentialProperty.Value) {
                throw "Credential binding disappeared during recovery for node: $NodeName"
            }

            $AfterCredentialJson = ConvertTo-Json `
                $AfterCredentialProperty.Value `
                -Depth 20 `
                -Compress

            if ($AfterCredentialJson -ne $CredentialSnapshot[$NodeName]) {
                throw "Credential binding changed during recovery for node: $NodeName"
            }
        }
    }
    finally {
        Pop-Location
    }
}
catch {
    $Failure = $_
}

try {
    & $StartN8n -WebhookUrl $PublicUrl -EditorBaseUrl $PublicUrl -PassThru | Out-Null
}
catch {
    if ($null -eq $Failure) {
        $Failure = $_
    }
    else {
        Write-Warning "Recovery failed and n8n restart also failed: $($_.Exception.Message)"
    }
}

if ($null -ne $Failure) {
    throw $Failure
}

Write-Host 'PHASE 4 WAVE 1 CODE CONTRACT RECOVERY: PASS'
Write-Host 'Workflow 08 was repaired and verified.'
Write-Host 'Workflow 01 and Workflow 02 remain repaired from the previous successful imports.'
Write-Host 'Credential bindings were preserved.'
Write-Host 'All three workflows remain inactive.'
Write-Host ("n8n editor: {0}/" -f $PublicUrl)
Write-Host ("Previous n8n process stopped: {0}" -f $Stopped)
Write-Host ("Recovery evidence directory: {0}" -f $RecoveryRoot)
