Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SisProjectRoot {
    $scriptsDirectory = Split-Path -Parent $PSScriptRoot
    return (Split-Path -Parent $scriptsDirectory)
}

function Get-SisRuntimeDirectory {
    param([string]$ProjectRoot)

    $configured = $env:SIS_RUNTIME_DIR
    if ([string]::IsNullOrWhiteSpace($configured)) {
        $configured = '.runtime'
    }

    if ([System.IO.Path]::IsPathRooted($configured)) {
        return [System.IO.Path]::GetFullPath($configured)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $configured))
}

function Import-SisEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$AllowMissing
    )

    $envPath = Join-Path $ProjectRoot '.env'
    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
        if ($AllowMissing) { return $false }
        throw "Missing .env. Run scripts/Initialize-Environment.ps1 first."
    }

    foreach ($rawLine in Get-Content -LiteralPath $envPath -Encoding UTF8) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }

        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { continue }

        $name = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            if ($value.Length -ge 2) { $value = $value.Substring(1, $value.Length - 2) }
        }

        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment variable name in .env: $name"
        }

        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }

    return $true
}

function Resolve-SisPath {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $Value))
}

function Get-SisN8nCommand {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $localCommand = Join-Path $ProjectRoot 'node_modules\.bin\n8n.cmd'
    if (Test-Path -LiteralPath $localCommand -PathType Leaf) {
        return $localCommand
    }

    $globalCommand = Get-Command 'n8n.cmd' -ErrorAction SilentlyContinue
    if ($null -ne $globalCommand) {
        return $globalCommand.Source
    }

    throw "n8n was not found. Run npm install from the project root."
}

function Get-SisNgrokCommand {
    $configured = $env:NGROK_COMMAND
    if ([string]::IsNullOrWhiteSpace($configured)) { $configured = 'ngrok' }

    if ([System.IO.Path]::IsPathRooted($configured) -and (Test-Path -LiteralPath $configured -PathType Leaf)) {
        return $configured
    }

    $command = Get-Command $configured -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "ngrok was not found. Install it and run ngrok config add-authtoken locally."
    }
    return $command.Source
}

function ConvertTo-SisVersion {
    param([Parameter(Mandatory = $true)][string]$Text)

    $match = [regex]::Match($Text, '(?<version>\d+\.\d+(?:\.\d+)?)')
    if (-not $match.Success) { throw "Could not parse version from: $Text" }

    $parts = $match.Groups['version'].Value.Split('.')
    while ($parts.Count -lt 3) { $parts += '0' }
    return [version]($parts -join '.')
}

function Test-SisNodeVersion {
    param([Parameter(Mandatory = $true)][version]$Version)

    $minimum = [version]'20.19.0'
    $maximumExclusive = [version]'25.0.0'
    return ($Version -ge $minimum -and $Version -lt $maximumExclusive)
}

function Test-SisTcpPort {
    param(
        [string]$HostName = '127.0.0.1',
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMilliseconds = 750
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch { return $false }
    finally { $client.Close() }
}

function Invoke-SisHttpProbe {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [int]$TimeoutSeconds = 10
    )

    $base = $BaseUrl.TrimEnd('/')
    $paths = @('/healthz', '/')
    $lastError = $null

    foreach ($path in $paths) {
        try {
            $response = Invoke-WebRequest -Uri ($base + $path) -UseBasicParsing -TimeoutSec $TimeoutSeconds -MaximumRedirection 2
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return [pscustomobject]@{
                    Success = $true
                    Url = ($base + $path)
                    StatusCode = [int]$response.StatusCode
                }
            }
        }
        catch { $lastError = $_.Exception.Message }
    }

    return [pscustomobject]@{
        Success = $false
        Url = $base
        StatusCode = $null
        Error = $lastError
    }
}

function Wait-SisHttpProbe {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [int]$TimeoutSeconds = 120,
        [int]$DelaySeconds = 2
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $result = Invoke-SisHttpProbe -BaseUrl $BaseUrl -TimeoutSeconds 5
        if ($result.Success) { return $result }
        Start-Sleep -Seconds $DelaySeconds
    } while ((Get-Date) -lt $deadline)

    return $result
}

function Write-SisPidFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$ProcessId
    )
    Set-Content -LiteralPath $Path -Value ([string]$ProcessId) -Encoding ASCII
}

function Read-SisPidFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $value = (Get-Content -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1).Trim()
    $parsed = 0
    if ([int]::TryParse($value, [ref]$parsed)) { return $parsed }
    return $null
}

function Stop-SisPidFileProcess {
    param([Parameter(Mandatory = $true)][string]$Path)

    $processId = Read-SisPidFile -Path $Path
    if ($null -eq $processId) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return $false
    }

    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        $taskkill = Get-Command 'taskkill.exe' -ErrorAction SilentlyContinue
        if ($null -ne $taskkill) {
            & $taskkill.Source /PID $processId /T /F 2>$null | Out-Null
        }
        else {
            Stop-Process -Id $processId -Force -ErrorAction Stop
        }
    }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($null -ne $process)
}
