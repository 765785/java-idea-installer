[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ToolkitRoot,

    [Parameter(Mandatory)]
    [int]$Port,

    [Parameter(Mandatory)]
    [string]$Token,

    [Parameter(Mandatory)]
    [string]$ProgressFile,

    [Parameter(Mandatory)]
    [string]$SentinelFile,

    [int]$IdleMinutes = 30
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$root = (Resolve-Path -LiteralPath $ToolkitRoot).Path
$runnerScript = Join-Path $root "repair-run.bat"
$launchFile = Join-Path $root "repair-launch.html"
$launchScript = Join-Path $root "repair-launch.js"
$localOrigin = "http://127.0.0.1:$Port"

if ($Token -notmatch "^[a-fA-F0-9]{64}$") {
    throw "Invalid bridge token."
}
if (-not (Test-Path -LiteralPath $runnerScript -PathType Leaf)) {
    throw "repair-run.bat was not found in the toolkit."
}
if (-not (Test-Path -LiteralPath $launchFile -PathType Leaf) -or -not (Test-Path -LiteralPath $launchScript -PathType Leaf)) {
    throw "Repair launch assets were not found in the toolkit."
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("$localOrigin/")
$listener.Start()

$script:CurrentJob = $null
$script:LastRequestAt = [DateTime]::UtcNow
$script:SeenRequests = @{}

function Write-HttpJson {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [object]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 6 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "application/json; charset=utf-8"
    $Context.Response.Headers["Cache-Control"] = "no-store"
    $Context.Response.Headers["X-Content-Type-Options"] = "nosniff"
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Test-Token {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or $Candidate.Length -ne $Token.Length) {
        return $false
    }
    $left = [Text.Encoding]::UTF8.GetBytes($Candidate.ToLowerInvariant())
    $right = [Text.Encoding]::UTF8.GetBytes($Token.ToLowerInvariant())
    $difference = 0
    for ($index = 0; $index -lt $left.Length; $index++) {
        $difference = $difference -bor ($left[$index] -bxor $right[$index])
    }
    return $difference -eq 0
}

function Test-Origin {
    param([string]$Origin)
    return $Origin -eq $localOrigin
}

function Send-File {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$Path,
        [string]$ContentType
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    $Context.Response.StatusCode = 200
    $Context.Response.ContentType = $ContentType
    $Context.Response.Headers["Cache-Control"] = "no-store"
    $Context.Response.Headers["X-Content-Type-Options"] = "nosniff"
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Start-RepairTerminal {
    $command = '"{0}"' -f $runnerScript
    $previous = $env:JAVA_SETUP_NO_BRIDGE
    $previousSentinel = $env:JAVA_SETUP_JOB_SENTINEL
    $env:JAVA_SETUP_NO_BRIDGE = "1"
    $env:JAVA_SETUP_JOB_SENTINEL = $SentinelFile
    try {
        return Start-Process -FilePath "cmd.exe" -ArgumentList @("/k", $command) -WorkingDirectory $root -PassThru
    } finally {
        $env:JAVA_SETUP_NO_BRIDGE = $previous
        $env:JAVA_SETUP_JOB_SENTINEL = $previousSentinel
    }
}

function Get-JobStatus {
    if (-not $script:CurrentJob) {
        return "idle"
    }
    if (Test-Path -LiteralPath $SentinelFile -PathType Leaf) {
        try {
            $exitCode = [int]((Get-Content -LiteralPath $SentinelFile -Raw).Trim())
            if ($exitCode -eq 0) {
                return "completed"
            }
            return "failed"
        } catch {
            return "failed"
        }
    }
    if (Test-Path -LiteralPath $ProgressFile -PathType Leaf) {
        try {
            $progress = Get-Content -LiteralPath $ProgressFile -Raw | ConvertFrom-Json
            if ($progress.status -eq "success") {
                return "completed"
            }
            if ($progress.status -in @("failed", "partial")) {
                return "failed"
            }
            if ($progress.status -eq "running") {
                try {
                    if ($progress.updatedAt -and ([DateTime]::UtcNow - [DateTime]$progress.updatedAt -gt [TimeSpan]::FromMinutes(5))) {
                        return "failed"
                    }
                } catch {
                    return "running"
                }
                return "running"
            }
        } catch {
            return "running"
        }
    }
    if ($script:CurrentJob.Process.HasExited -and ([DateTime]::UtcNow - $script:CurrentJob.StartedAtUtc -gt [TimeSpan]::FromSeconds(20))) {
        return "failed"
    }
    return "running"
}

$pendingContext = $null
while ($listener.IsListening) {
    $jobActive = $script:CurrentJob -and (Get-JobStatus) -eq "running"
    if (-not $jobActive -and [DateTime]::UtcNow - $script:LastRequestAt -gt [TimeSpan]::FromMinutes($IdleMinutes)) {
        break
    }

    $context = $null
    try {
        if (-not $pendingContext) {
            $pendingContext = $listener.GetContextAsync()
        }
        if (-not $pendingContext.Wait(1000)) {
            continue
        }
        $context = $pendingContext.Result
        $pendingContext = $null
        $script:LastRequestAt = [DateTime]::UtcNow
        $path = $context.Request.Url.AbsolutePath

        if ($context.Request.HttpMethod -eq "GET" -and $path -eq "/health") {
            Write-HttpJson -Context $context -StatusCode 200 -Body @{ status = "ok" }
            continue
        }
        if ($context.Request.HttpMethod -eq "GET" -and $path -eq "/launch") {
            Send-File -Context $context -Path $launchFile -ContentType "text/html; charset=utf-8"
            continue
        }
        if ($context.Request.HttpMethod -eq "GET" -and $path -eq "/repair-launch.js") {
            Send-File -Context $context -Path $launchScript -ContentType "text/javascript; charset=utf-8"
            continue
        }
        if ($context.Request.HttpMethod -eq "GET" -and $path -eq "/api/status") {
            if (-not (Test-Token -Candidate $context.Request.Headers["X-Java-Setup-Token"])) {
                Write-HttpJson -Context $context -StatusCode 403 -Body @{ status = "error"; message = "Invalid token." }
                continue
            }
            if (-not $script:CurrentJob) {
                Write-HttpJson -Context $context -StatusCode 200 -Body @{ status = "idle" }
                continue
            }
            $state = Get-JobStatus
            $progressPayload = $null
            if (Test-Path -LiteralPath $ProgressFile -PathType Leaf) {
                try {
                    $progressPayload = Get-Content -LiteralPath $ProgressFile -Raw | ConvertFrom-Json
                } catch {
                    $progressPayload = $null
                }
            }
            Write-HttpJson -Context $context -StatusCode 200 -Body @{
                status = $state
                jobId = $script:CurrentJob.JobId
                exitCode = if ($script:CurrentJob.Process.HasExited) { $script:CurrentJob.Process.ExitCode } else { $null }
                progress = $progressPayload
            }
            continue
        }
        if ($context.Request.HttpMethod -eq "POST" -and $path -eq "/api/repair-all") {
            if (-not (Test-Origin -Origin $context.Request.Headers["Origin"])) {
                Write-HttpJson -Context $context -StatusCode 403 -Body @{ status = "error"; message = "Invalid origin." }
                continue
            }
            if (-not (Test-Token -Candidate $context.Request.Headers["X-Java-Setup-Token"])) {
                Write-HttpJson -Context $context -StatusCode 403 -Body @{ status = "error"; message = "Invalid token." }
                continue
            }
            if ($context.Request.ContentLength64 -gt 4096) {
                Write-HttpJson -Context $context -StatusCode 413 -Body @{ status = "error"; message = "Request too large." }
                continue
            }

            $reader = [IO.StreamReader]::new($context.Request.InputStream, [Text.Encoding]::UTF8)
            try {
                $payload = $reader.ReadToEnd() | ConvertFrom-Json
            } finally {
                $reader.Dispose()
            }
            $action = if ($payload -and $payload.PSObject.Properties.Name -contains "action") { [string]$payload.action } else { "" }
            $protocolVersion = if ($payload -and $payload.PSObject.Properties.Name -contains "protocolVersion") { [int]$payload.protocolVersion } else { 0 }
            $requestId = if ($payload -and $payload.PSObject.Properties.Name -contains "requestId") { [string]$payload.requestId } else { "" }
            if ($action -ne "fix-all" -or $protocolVersion -ne 2 -or $requestId -notmatch "^[a-fA-F0-9]{32}$") {
                Write-HttpJson -Context $context -StatusCode 400 -Body @{ status = "error"; message = "Invalid repair request." }
                continue
            }
            if ($script:CurrentJob -and (Get-JobStatus) -eq "running" -and $script:CurrentJob.RequestId -ne $requestId) {
                Write-HttpJson -Context $context -StatusCode 409 -Body @{ status = "busy"; message = "A repair task is already running." }
                continue
            }
            if ($script:SeenRequests.ContainsKey($requestId)) {
                Write-HttpJson -Context $context -StatusCode 200 -Body @{ status = "accepted"; jobId = $script:SeenRequests[$requestId].JobId }
                continue
            }

            if (Test-Path -LiteralPath $ProgressFile -PathType Leaf) {
                Remove-Item -LiteralPath $ProgressFile -Force
            }
            if (Test-Path -LiteralPath $SentinelFile -PathType Leaf) {
                Remove-Item -LiteralPath $SentinelFile -Force
            }
            $process = Start-RepairTerminal
            $jobId = [Guid]::NewGuid().ToString("N")
            $script:CurrentJob = [pscustomobject]@{
                JobId = $jobId
                RequestId = $requestId
                Process = $process
                StartedAt = [DateTime]::UtcNow.ToString("o")
                StartedAtUtc = [DateTime]::UtcNow
            }
            $script:SeenRequests[$requestId] = $script:CurrentJob
            Write-HttpJson -Context $context -StatusCode 200 -Body @{ status = "accepted"; jobId = $jobId }
            continue
        }

        Write-HttpJson -Context $context -StatusCode 404 -Body @{ status = "error"; message = "Not found." }
    } catch {
        try {
            [Console]::Error.WriteLine("Repair bridge error: {0}" -f $_.Exception.Message)
        } catch {}
        if ($context) {
            try {
                Write-HttpJson -Context $context -StatusCode 500 -Body @{ status = "error"; message = "Repair bridge error." }
            } catch {}
        }
    }
}

$listener.Stop()
$listener.Close()
