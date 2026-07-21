[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Sis.Runtime.ps1')

$ProjectRoot = Get-SisProjectRoot
Import-SisEnvironment -ProjectRoot $ProjectRoot | Out-Null

$N8nCli = Join-Path $ProjectRoot 'node_modules\.bin\n8n.cmd'
if (-not (Test-Path -LiteralPath $N8nCli -PathType Leaf)) {
    throw "Local n8n CLI was not found: $N8nCli"
}

$StartN8n = Join-Path $PSScriptRoot 'Start-N8n.ps1'
if (-not (Test-Path -LiteralPath $StartN8n -PathType Leaf)) {
    throw "Start-N8n.ps1 was not found: $StartN8n"
}

$ApiUrl = $env:NGROK_API_URL
if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    $ApiUrl = 'http://127.0.0.1:4040/api/tunnels'
}

try {
    $NgrokStatus = Invoke-RestMethod -Uri $ApiUrl -Method Get -TimeoutSec 10
}
catch {
    throw 'The active ngrok tunnel could not be read. Keep ngrok running before applying the live workflow repair.'
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
$RepairRoot = Join-Path $RuntimeDirectory ('repairs\phase4-wave1-code-contract-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $RepairRoot -Force | Out-Null

$Targets = @(
    @{
        Id = '29963761-c757-52ed-a725-270112b9a5cc'
        Source = 'workflows\01-student-intake.json'
    },
    @{
        Id = 'a6e31ab8-3bd7-55b8-8a2c-0a5a43ebf7b5'
        Source = 'workflows\02-enrollment-lifecycle.json'
    },
    @{
        Id = '3b0adf1b-93eb-51df-872a-76485036e76b'
        Source = 'workflows\08-notification-dispatcher.json'
    }
)

$Stopped = Stop-SisPidFileProcess -Path $N8nPidPath
Start-Sleep -Seconds 2

$Failure = $null
$Imported = 0

try {
    Push-Location $ProjectRoot
    try {
        foreach ($Target in $Targets) {
            $Id = [string]$Target.Id
            $SourcePath = Join-Path $ProjectRoot ([string]$Target.Source)
            $ExportPath = Join-Path $RepairRoot ($Id + '.export.json')
            $PatchedPath = Join-Path $RepairRoot ($Id + '.patched.json')

            if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
                throw "Missing repaired source workflow: $SourcePath"
            }

            & $N8nCli export:workflow "--id=$Id" "--output=$ExportPath" --pretty
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ExportPath)) {
                throw "Could not export live workflow $Id."
            }

            $ParsedLive = Get-Content -LiteralPath $ExportPath -Raw | ConvertFrom-Json
            $LiveWorkflow = if ($ParsedLive -is [System.Array]) {
                $ParsedLive[0]
            }
            else {
                $ParsedLive
            }

            $SourceWorkflow = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json
            $SourceCodeNodes = @(
                $SourceWorkflow.nodes |
                    Where-Object { $_.type -eq 'n8n-nodes-base.code' }
            )

            foreach ($SourceNode in $SourceCodeNodes) {
                $LiveNode = @(
                    $LiveWorkflow.nodes |
                        Where-Object {
                            $_.type -eq 'n8n-nodes-base.code' -and
                            $_.name -eq $SourceNode.name
                        }
                )

                if ($LiveNode.Count -ne 1) {
                    throw "Live workflow $Id does not contain exactly one Code node named '$($SourceNode.name)'."
                }

                $LiveNode[0].parameters.mode = $SourceNode.parameters.mode
                $LiveNode[0].parameters.jsCode = $SourceNode.parameters.jsCode
            }

            # Preserve every live setting—including credential IDs, selected
            # Google files/tabs and workflow ownership—and replace only the
            # Code-node mode and source.
            $Json = ConvertTo-Json -InputObject @($LiveWorkflow) -Depth 100
            [IO.File]::WriteAllText(
                $PatchedPath,
                $Json,
                [Text.UTF8Encoding]::new($false)
            )

            & $N8nCli import:workflow "--input=$PatchedPath" --activeState=false
            if ($LASTEXITCODE -ne 0) {
                throw "Could not import repaired live workflow $Id."
            }

            $Imported += 1
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
    $N8n = & $StartN8n `
        -WebhookUrl $PublicUrl `
        -EditorBaseUrl $PublicUrl `
        -PassThru
}
catch {
    if ($null -eq $Failure) {
        $Failure = $_
    }
    else {
        Write-Warning "Workflow repair failed and n8n restart also failed: $($_.Exception.Message)"
    }
}

if ($null -ne $Failure) {
    throw $Failure
}

if ($Imported -ne 3) {
    throw "Expected to repair three workflows, repaired $Imported."
}

Write-Host 'PHASE 4 WAVE 1 LIVE CODE CONTRACT REPAIR: PASS'
Write-Host 'Repaired three live workflows while preserving credential IDs and selected Google assets.'
Write-Host 'All three workflows remain inactive.'
Write-Host ("n8n editor: {0}/" -f $PublicUrl)
Write-Host ("Previous n8n process stopped: {0}" -f $Stopped)
Write-Host ("Repair backup directory: {0}" -f $RepairRoot)
