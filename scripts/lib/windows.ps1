[CmdletBinding()]
param(
    [ValidateSet("detect", "install", "uninstall", "verify")]
    [string]$Action = "detect",

    [ValidateSet("java_home", "path", "multiple_jdks", "idea_repair", "vc_runtime", "port")]
    [string]$Fix,

    [switch]$FixAll,
    [switch]$Resume,
    [switch]$DryRun,
    [switch]$KeepSettings,
    [string]$OutputDirectory,

    [ValidatePattern("^https?://")]
    [string]$OpenPage = "https://765785.github.io/java-idea-installer/"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:ToolVersion = "1.0.0"
$script:JdkTargetVersion = 25
$script:JdkDistribution = "temurin"
$script:MirrorMode = "auto"
$script:IdeaFallbackEnabled = $true
$script:PublicSite = "https://765785.github.io/java-idea-installer"
$script:LogLines = [System.Collections.Generic.List[string]]::new()
$script:ProgressSteps = [System.Collections.Generic.List[object]]::new()
$script:StartedAt = [DateTime]::UtcNow.ToString("o")

function Get-Timestamp {
    return [DateTime]::UtcNow.ToString("o")
}

function Get-ReportDirectory {
    if ($OutputDirectory) {
        $directory = [System.IO.Path]::GetFullPath($OutputDirectory)
    } else {
        $directory = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads\java-setup-reports"
    }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    return $directory
}

function Write-Log {
    param(
        [ValidateSet("信息", "完成", "提醒", "错误")]
        [string]$Level,
        [string]$Message
    )
    $line = "[{0}] {1} {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
    $script:LogLines.Add($line)
    if ($script:LogLines.Count -gt 160) {
        $script:LogLines.RemoveAt(0)
    }
    $color = switch ($Level) {
        "完成" { "Green" }
        "提醒" { "Yellow" }
        "错误" { "Red" }
        default { "Cyan" }
    }
    Write-Host $line -ForegroundColor $color
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temporary = Join-Path $directory ("{0}.{1}.tmp" -f [System.IO.Path]::GetFileName($Path), [Guid]::NewGuid().ToString("N"))
    $json = $Data | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Initialize-Progress {
    param(
        [string]$ProgressAction,
        [array]$Steps
    )

    $script:ProgressSteps.Clear()
    foreach ($step in $Steps) {
        $script:ProgressSteps.Add([pscustomobject]@{
                id = [string]$step.id
                label = [string]$step.label
                status = "pending"
                estimatedSeconds = [int]$step.estimatedSeconds
                message = ""
            })
    }
    $script:StartedAt = [DateTime]::UtcNow.ToString("o")
    $script:ProgressAction = $ProgressAction
    Write-ProgressState -Status "running" -CurrentStep 0 -Percent 0 -Message "准备开始"
}

function Set-ProgressStep {
    param(
        [int]$Index,
        [ValidateSet("pending", "running", "complete", "failed")]
        [string]$Status,
        [string]$Message = "",
        [int]$Percent = -1
    )

    if ($Index -lt 0 -or $Index -ge $script:ProgressSteps.Count) {
        return
    }

    $script:ProgressSteps[$Index].status = $Status
    $script:ProgressSteps[$Index].message = $Message
    if ($Percent -lt 0) {
        $Percent = [Math]::Round((($Index + ($(if ($Status -eq "complete") { 1 } else { 0.35 }))) / $script:ProgressSteps.Count) * 100)
    }
    Write-ProgressState -Status "running" -CurrentStep $Index -Percent $Percent -Message $Message
}

function Write-ProgressState {
    param(
        [ValidateSet("running", "success", "partial", "failed")]
        [string]$Status,
        [int]$CurrentStep,
        [int]$Percent,
        [string]$Message,
        [object]$Result = $null
    )

    if (-not $script:ProgressDirectory) {
        return
    }

    $payload = [ordered]@{
        schemaVersion = 1
        action = $script:ProgressAction
        status = $Status
        currentStep = $CurrentStep
        totalSteps = $script:ProgressSteps.Count
        percent = [Math]::Max(0, [Math]::Min(100, $Percent))
        steps = @($script:ProgressSteps)
        startedAt = $script:StartedAt
        updatedAt = Get-Timestamp
        message = $Message
        result = $Result
        log = ($script:LogLines -join [Environment]::NewLine)
    }
    Write-JsonAtomic -Data $payload -Path (Join-Path $script:ProgressDirectory "progress.json")
}

function Initialize-ProgressPage {
    param([string]$ProgressAction)

    if ([string]::IsNullOrWhiteSpace($ProgressAction)) {
        throw "ProgressAction is required"
    }
    $reportDirectory = Get-ReportDirectory
    $progressDirectory = Join-Path $reportDirectory "progress"
    New-Item -ItemType Directory -Force -Path $progressDirectory | Out-Null
    $sourceDirectory = Split-Path -Parent $PSScriptRoot
    foreach ($fileName in @("progress.html", "progress.js")) {
        $source = Join-Path $sourceDirectory $fileName
        if (-not (Test-Path -LiteralPath $source)) {
            try {
                $remote = ($script:PublicSite.TrimEnd("/") + "/scripts/" + $fileName)
                Invoke-WebRequest -UseBasicParsing -Uri $remote -OutFile $source -TimeoutSec 30
            } catch {
                Write-Verbose "Could not download $fileName from the public site."
            }
        }
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $progressDirectory $fileName) -Force
        }
    }

    $serverScript = Join-Path $PSScriptRoot "progress-server.ps1"
    if (-not (Test-Path -LiteralPath $serverScript)) {
        try {
            $remote = ($script:PublicSite.TrimEnd("/") + "/scripts/lib/progress-server.ps1")
            Invoke-WebRequest -UseBasicParsing -Uri $remote -OutFile $serverScript -TimeoutSec 30
        } catch {
            Write-Verbose "Could not download the progress server helper."
        }
    }
    $port = 8765
    $server = $null
    $token = [Guid]::NewGuid().ToString("N")
    if (Test-Path -LiteralPath $serverScript) {
        for ($candidate = $port; $candidate -lt ($port + 20); $candidate++) {
            $inUse = Get-NetTCPConnection -State Listen -LocalPort $candidate -ErrorAction SilentlyContinue
            if (-not $inUse) {
                $port = $candidate
                $arguments = @(
                    "-NoLogo",
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", ('"{0}"' -f $serverScript),
                    "-Directory", ('"{0}"' -f $progressDirectory),
                    "-Port", [string]$port,
                    "-Token", $token
                )
                $server = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru
                Start-Sleep -Milliseconds 700
                break
            }
        }
    }

    $script:ProgressDirectory = $progressDirectory
    $returnUrl = [Uri]::EscapeDataString($OpenPage)
    if ($server -and -not $server.HasExited) {
        return "http://127.0.0.1:$port/progress.html?return=$returnUrl&token=$token"
    }

    $localPage = Join-Path $progressDirectory "progress.html"
    return ([Uri]$localPage).AbsoluteUri + "?return=$returnUrl"
}

function Open-ProgressPage {
    param([string]$ProgressAction)
    if ($FixAll -or $env:JAVA_SETUP_NO_UI -eq "1") {
        $reportDirectory = Get-ReportDirectory
        $script:ProgressDirectory = Join-Path $reportDirectory "progress"
        New-Item -ItemType Directory -Force -Path $script:ProgressDirectory | Out-Null
        return ""
    }
    try {
        $url = Initialize-ProgressPage -ProgressAction $ProgressAction
        Start-Process $url | Out-Null
        return $url
    } catch {
        Write-Log -Level "提醒" -Message "无法自动打开本地进度页：$($_.Exception.Message)"
        return ""
    }
}

function Get-FreeLocalPort {
    param(
        [int]$StartPort = 8790,
        [int]$Count = 30
    )

    for ($candidate = $StartPort; $candidate -lt ($StartPort + $Count); $candidate++) {
        if (-not (Get-NetTCPConnection -State Listen -LocalPort $candidate -ErrorAction SilentlyContinue)) {
            return $candidate
        }
    }
    return 0
}

function Start-RepairBridge {
    param([object]$DetectionResult)

    if ($FixAll -or $env:JAVA_SETUP_NO_UI -eq "1") {
        return $null
    }

    $fixableCount = @($DetectionResult.health | Where-Object { $_ -and $_.fixable -eq $true }).Count
    if ($fixableCount -eq 0 -and $DetectionResult.summary.errors -eq 0) {
        return $null
    }

    $toolkitRoot = Split-Path -Parent $PSScriptRoot
    $bridgeScript = Join-Path $toolkitRoot "repair-bridge.ps1"
    if (-not (Test-Path -LiteralPath $bridgeScript -PathType Leaf)) {
        return $null
    }

    $port = Get-FreeLocalPort
    if ($port -eq 0) {
        return $null
    }

    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] 32
        $rng.GetBytes($bytes)
        $token = ([BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $rng.Dispose()
    }

    $reportDirectory = Get-ReportDirectory
    $stdout = Join-Path $reportDirectory "repair-bridge.log"
    $stderr = Join-Path $reportDirectory "repair-bridge.error.log"
    $progressFile = Join-Path $reportDirectory "progress\progress.json"
    $sentinelFile = Join-Path $reportDirectory "progress\repair-job.exit"
    $arguments = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $bridgeScript),
        "-ToolkitRoot", ('"{0}"' -f $toolkitRoot),
        "-Port", [string]$port,
        "-Token", $token,
        "-ProgressFile", ('"{0}"' -f $progressFile),
        "-SentinelFile", ('"{0}"' -f $sentinelFile),
        "-IdleMinutes", "30"
    )

    try {
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList $arguments `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) {
            return $null
        }
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 3
        if ($health.status -ne "ok") {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            return $null
        }
        return [pscustomobject]@{
            port = $port
            token = $token
        }
    } catch {
        Write-Log -Level "提醒" -Message "无法启动本地修复助手：$($_.Exception.Message)"
        return $null
    }
}

function Get-PeVersion {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 0
    }
    $normalized = $Value.Trim()
    if ($normalized.StartsWith("1.")) {
        $parts = $normalized.Split(".")
        if ($parts.Count -gt 1) {
            return [int]($parts[1] -replace "\D.*$", "")
        }
    }
    $match = [regex]::Match($normalized, "\d+")
    if ($match.Success) {
        return [int]$match.Value
    }
    return 0
}

function Compare-VersionValue {
    param(
        [string]$Left,
        [string]$Right
    )

    try {
        $leftVersion = [version]([regex]::Match($Left, "\d+(\.\d+){0,3}").Value)
        $rightVersion = [version]([regex]::Match($Right, "\d+(\.\d+){0,3}").Value)
        return $leftVersion.CompareTo($rightVersion)
    } catch {
        return 0
    }
}

function Get-JavaVersionAtPath {
    param([string]$JavaPath)
    if ([string]::IsNullOrWhiteSpace($JavaPath) -or -not (Test-Path -LiteralPath $JavaPath)) {
        return $null
    }

    try {
        $output = & $JavaPath -version 2>&1 | Out-String
        $match = [regex]::Match($output, '"([^"]+)"')
        if (-not $match.Success) {
            return $null
        }
        $version = $match.Groups[1].Value
        return [pscustomobject]@{
            version = $version
            major = Get-PeVersion $version
        }
    } catch {
        return $null
    }
}

function Convert-JavaExeToHome {
    param([string]$JavaExe)
    if ([string]::IsNullOrWhiteSpace($JavaExe)) {
        return $null
    }
    $resolved = [System.IO.Path]::GetFullPath($JavaExe)
    $binDirectory = Split-Path -Parent $resolved
    if ((Split-Path -Leaf $binDirectory) -ieq "bin") {
        return Split-Path -Parent $binDirectory
    }
    return $null
}

function Add-JavaCandidate {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$JavaHomePath,
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($JavaHomePath)) {
        return
    }

    try {
        $fullHome = [System.IO.Path]::GetFullPath($JavaHomePath.Trim())
    } catch {
        return
    }

    $javaExe = Join-Path $fullHome "bin\java.exe"
    if (-not (Test-Path -LiteralPath $javaExe -PathType Leaf)) {
        return
    }
    $version = Get-JavaVersionAtPath $javaExe
    if (-not $version) {
        return
    }

    $existing = $Candidates | Where-Object {
        try {
            [System.IO.Path]::GetFullPath($_.path) -ieq $fullHome
        } catch {
            $false
        }
    } | Select-Object -First 1
    if ($existing) {
        return
    }

    $Candidates.Add([pscustomobject]@{
            path = $fullHome
            javaExe = $javaExe
            version = [string]$version.version
            major = [int]$version.major
            source = $Source
        })
}

function Get-JavaCandidates {
    $candidates = [System.Collections.Generic.List[object]]::new()

    if ($env:JAVA_HOME) {
        Add-JavaCandidate -Candidates $candidates -Home $env:JAVA_HOME -Source "JAVA_HOME"
        if ((Split-Path -Leaf $env:JAVA_HOME.TrimEnd("\")) -ieq "bin") {
            Add-JavaCandidate -Candidates $candidates -Home (Split-Path -Parent $env:JAVA_HOME.TrimEnd("\")) -Source "JAVA_HOME 上级目录"
        }
    }

    $javaCommand = Get-Command java.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($javaCommand) {
        $javaHomeFromPath = Convert-JavaExeToHome $javaCommand.Source
        Add-JavaCandidate -Candidates $candidates -Home $javaHomeFromPath -Source "PATH"
    }

    $searchRoots = @(
        (Join-Path $env:ProgramFiles "Eclipse Adoptium"),
        (Join-Path $env:ProgramFiles "Java"),
        (Join-Path $env:ProgramFiles "Microsoft"),
        (Join-Path $env:LOCALAPPDATA "Programs\Eclipse Adoptium")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $searchRoots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "(?i)jdk|java" } |
            ForEach-Object { Add-JavaCandidate -Candidates $candidates -Home $_.FullName -Source "安装目录" }
    }

    $registryRoots = @(
        "HKLM:\SOFTWARE\JavaSoft\JDK",
        "HKLM:\SOFTWARE\JavaSoft\Java Development Kit",
        "HKCU:\SOFTWARE\JavaSoft\JDK"
    )
    foreach ($registryRoot in $registryRoots) {
        if (-not (Test-Path $registryRoot)) {
            continue
        }
        Get-ChildItem $registryRoot -ErrorAction SilentlyContinue | ForEach-Object {
            $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            Add-JavaCandidate -Candidates $candidates -Home $item.JavaHome -Source "注册表"
        }
    }

    return @($candidates | Sort-Object major, version -Descending)
}

function Select-JavaHome {
    param([array]$Candidates)
    $validCandidates = @($Candidates | Where-Object {
            $_ -and $_.PSObject.Properties.Name -contains "major" -and $_.PSObject.Properties.Name -contains "version"
        })
    $compatible = @($validCandidates | Where-Object { [int]$_.major -ge $script:JdkTargetVersion })
    if ($compatible.Count -gt 0) {
        return $compatible | Sort-Object major, version -Descending | Select-Object -First 1
    }
    return $validCandidates | Sort-Object major, version -Descending | Select-Object -First 1
}

function Get-IdeaInstallations {
    $installations = [System.Collections.Generic.List[object]]::new()
    $registryRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($root in $registryRoots) {
        Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object {
                $_.PSObject.Properties.Name -contains "DisplayName" -and
                $_.DisplayName -match "(?i)IntelliJ IDEA Community"
            } |
            ForEach-Object {
                $installLocation = $_.InstallLocation
                $version = [string]$_.DisplayVersion
                if ($installLocation -and (Test-Path -LiteralPath $installLocation)) {
                    $productInfo = Join-Path $installLocation "product-info.json"
                    if (Test-Path -LiteralPath $productInfo) {
                        try {
                            $info = Get-Content -LiteralPath $productInfo -Raw | ConvertFrom-Json
                            if ($info.version) { $version = [string]$info.version }
                        } catch {
                            Write-Verbose "Ignoring invalid product-info.json at $productInfo"
                        }
                    }
                }
                $installations.Add([pscustomobject]@{
                        path = $installLocation
                        version = $version
                        build = [string]$_.DisplayVersion
                        source = "注册表"
                    })
            }
    }

    $commonRoots = @(
        (Join-Path $env:ProgramFiles "JetBrains"),
        (Join-Path $env:LOCALAPPDATA "Programs")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $commonRoots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "(?i)IntelliJ IDEA Community" } |
            ForEach-Object {
                $version = ""
                $productInfo = Join-Path $_.FullName "product-info.json"
                if (Test-Path -LiteralPath $productInfo) {
                    try {
                        $info = Get-Content -LiteralPath $productInfo -Raw | ConvertFrom-Json
                        $version = [string]$info.version
                    } catch {
                        Write-Verbose "Ignoring invalid product-info.json at $productInfo"
                    }
                }
                $installations.Add([pscustomobject]@{
                        path = $_.FullName
                        version = $version
                        build = ""
                        source = "安装目录"
                    })
            }
    }

    return @($installations | Sort-Object { Get-PeVersion $_.version } -Descending -Unique)
}

function Get-LatestIdeaRelease {
    $result = [ordered]@{
        status = "unavailable"
        version = $null
        build = $null
        windowsUrl = $null
        checksum = $null
        message = ""
    }

    try {
        $uri = "https://data.services.jetbrains.com/products/releases?code=IIC&latest=true&type=release"
        $response = Invoke-RestMethod -Uri $uri -TimeoutSec 20 -Headers @{ "User-Agent" = "java-idea-installer/$script:ToolVersion" }
        $release = @($response.IIC)[0]
        if (-not $release.version) {
            throw "JetBrains 响应中缺少 version"
        }
        $result.status = "ok"
        $result.version = [string]$release.version
        $result.build = [string]$release.build
        $result.windowsUrl = [string]$release.downloads.windows.link
        $result.checksum = [string]$release.downloads.windows.checksumLink
        $result.message = "已获取 JetBrains 官方最新版"
    } catch {
        $result.message = "无法确认最新版，按已安装处理"
    }

    return [pscustomobject]$result
}

function Get-NetworkStatus {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingComputerNameHardcoded", "", Justification = "Fixed connectivity probes are intentional and contain no user data.")]
    param()

    $domestic = $false
    $international = $false
    try {
        $domestic = Test-NetConnection -ComputerName "mirrors.tuna.tsinghua.edu.cn" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    } catch {
        $domestic = $false
    }
    try {
        $international = Test-NetConnection -ComputerName "github.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    } catch {
        $international = $false
    }

    return [pscustomobject]@{
        status = if ($domestic -and $international) { "ok" } elseif ($domestic -or $international) { "partial" } else { "unavailable" }
        mirrorMode = $script:MirrorMode
        selectedMirror = if ($script:MirrorMode -eq "always" -or ($script:MirrorMode -eq "auto" -and $domestic -and -not $international)) { "tuna" } else { "default" }
        domesticReachable = $domestic
        internationalReachable = $international
    }
}

function New-DetectionResult {
    param(
        [array]$Candidates,
        [array]$Ideas,
        [object]$LatestIdea,
        [object]$Network
    )

    $selectedJdk = Select-JavaHome -Candidates $Candidates
    $health = [System.Collections.Generic.List[object]]::new()

    if (-not $selectedJdk) {
        $jdk = [ordered]@{
            status = "missing"
            version = $null
            path = $null
            targetVersion = $script:JdkTargetVersion
            source = $null
            message = "未检测到可用 JDK"
        }
        $health.Add([ordered]@{
                id = "jdk_missing"
                title = "Java (JDK) 未安装"
                severity = "error"
                fixable = $true
                action = "java_home"
                message = "需要安装 JDK $script:JdkTargetVersion LTS"
            })
    } elseif ($selectedJdk.major -lt $script:JdkTargetVersion) {
        $jdk = [ordered]@{
            status = "outdated"
            version = $selectedJdk.version
            path = $selectedJdk.path
            targetVersion = $script:JdkTargetVersion
            source = $selectedJdk.source
            message = "当前版本低于目标版本 $script:JdkTargetVersion"
        }
    } else {
        $jdk = [ordered]@{
            status = "ok"
            version = $selectedJdk.version
            path = $selectedJdk.path
            targetVersion = $script:JdkTargetVersion
            source = $selectedJdk.source
            message = "可用于 Java 开发"
        }
    }

    if (@($Candidates).Count -gt 1) {
        $health.Add([ordered]@{
                id = "multiple_jdks"
                title = "检测到多个 JDK"
                severity = "warning"
                fixable = $true
                action = "multiple_jdks"
                message = "将优先使用版本最高且满足目标要求的 JDK"
            })
    }

    $selectedIdea = @($Ideas | Where-Object { $_ -and $_.PSObject.Properties.Name -contains "version" }) |
        Sort-Object { Get-PeVersion $_.version } -Descending |
        Select-Object -First 1
    if (-not $selectedIdea) {
        $idea = [ordered]@{
            status = "missing"
            version = $null
            latestVersion = $LatestIdea.version
            build = $null
            path = $null
            message = "未检测到 IntelliJ IDEA Community"
        }
        $health.Add([ordered]@{
                id = "idea_repair"
                title = "IntelliJ IDEA Community 未安装"
                severity = "error"
                fixable = $true
                action = "idea_repair"
                message = "安装最新版 IDEA Community"
            })
    } elseif ($LatestIdea.status -ne "ok") {
        $idea = [ordered]@{
            status = "ok"
            version = $selectedIdea.version
            latestVersion = $null
            build = $selectedIdea.build
            path = $selectedIdea.path
            message = "无法确认最新版，按已安装处理"
        }
    } elseif ((Compare-VersionValue $selectedIdea.version $LatestIdea.version) -lt 0) {
        $idea = [ordered]@{
            status = "outdated"
            version = $selectedIdea.version
            latestVersion = $LatestIdea.version
            build = $selectedIdea.build
            path = $selectedIdea.path
            message = "当前版本可升级到 $($LatestIdea.version)"
        }
    } else {
        $idea = [ordered]@{
            status = "ok"
            version = $selectedIdea.version
            latestVersion = $LatestIdea.version
            build = $selectedIdea.build
            path = $selectedIdea.path
            message = "已是最新版本"
        }
    }

    $javaHomeValue = $env:JAVA_HOME
    if ([string]::IsNullOrWhiteSpace($javaHomeValue)) {
        $javaHome = [ordered]@{
            status = "missing"
            path = $null
            version = $null
            message = "JAVA_HOME 未设置"
        }
        $health.Add([ordered]@{
                id = "java_home"
                title = "JAVA_HOME 未设置"
                severity = "warning"
                fixable = $true
                action = "java_home"
                message = "自动指向选中的 JDK"
            })
    } else {
        $homeJava = Join-Path $javaHomeValue "bin\java.exe"
        $homeVersion = Get-JavaVersionAtPath $homeJava
        if (-not $homeVersion) {
            $javaHome = [ordered]@{
                status = "invalid"
                path = $javaHomeValue
                version = $null
                message = "JAVA_HOME 指向的路径无效"
            }
            $health.Add([ordered]@{
                    id = "java_home"
                    title = "JAVA_HOME 指向错误路径"
                    severity = "warning"
                    fixable = $true
                    action = "java_home"
                    message = "自动重新检测并设置有效 JDK"
                })
        } elseif ($homeVersion.major -lt $script:JdkTargetVersion) {
            $javaHome = [ordered]@{
                status = "mismatch"
                path = $javaHomeValue
                version = $homeVersion.version
                message = "JAVA_HOME 版本低于目标版本"
            }
        } else {
            $javaHome = [ordered]@{
                status = "ok"
                path = $javaHomeValue
                version = $homeVersion.version
                message = "JAVA_HOME 配置有效"
            }
        }
    }

    $pathEntries = @($env:Path -split ";" | Where-Object { $_ })
    if ($selectedJdk -and -not ($pathEntries | Where-Object {
                try { [System.IO.Path]::GetFullPath($_).TrimEnd("\") -ieq [System.IO.Path]::GetFullPath((Join-Path $selectedJdk.path "bin")).TrimEnd("\") } catch { $false }
            })) {
        $health.Add([ordered]@{
                id = "path"
                title = "PATH 缺少 JDK bin"
                severity = "warning"
                fixable = $true
                action = "path"
                message = "自动追加选中 JDK 的 bin 目录"
            })
    }

    $componentItems = @($jdk, $idea, $javaHome)
    $componentWarnings = @($componentItems | Where-Object { $_.status -notin @("ok") }).Count
    $errors = @($componentItems | Where-Object { $_.status -in @("missing", "invalid", "error") }).Count

    $osVersion = (Get-CimInstance Win32_OperatingSystem).Version
    return [ordered]@{
        schemaVersion = 1
        toolVersion = $script:ToolVersion
        generatedAt = Get-Timestamp
        os = [ordered]@{
            family = "windows"
            version = $osVersion
            architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
        }
        network = [ordered]@{
            status = $Network.status
            mirrorMode = $Network.mirrorMode
            selectedMirror = $Network.selectedMirror
            domesticReachable = $Network.domesticReachable
            internationalReachable = $Network.internationalReachable
            ideaVersionCheck = $LatestIdea.status
            message = $LatestIdea.message
        }
        components = [ordered]@{
            jdk = $jdk
            idea = $idea
            javaHome = $javaHome
        }
        health = @($health)
        summary = [ordered]@{
            ok = 3 - $componentWarnings
            warnings = [Math]::Max(0, $componentWarnings - $errors)
            errors = $errors
        }
    }
}

function Invoke-Detection {
    Write-Log -Level "信息" -Message "正在检测 Windows、JDK、IDEA 和环境变量..."
    $candidates = Get-JavaCandidates
    $ideas = Get-IdeaInstallations
    $latestIdea = Get-LatestIdeaRelease
    $network = Get-NetworkStatus
    $network | Add-Member -NotePropertyName ideaVersionCheck -NotePropertyValue $latestIdea.status -Force
    $result = New-DetectionResult -Candidates $candidates -Ideas $ideas -LatestIdea $latestIdea -Network $network

    $reportDirectory = Get-ReportDirectory
    $resultPath = Join-Path $reportDirectory "detection_result.json"
    Write-JsonAtomic -Data $result -Path $resultPath

    Write-Host ""
    Write-Host "检测报告" -ForegroundColor White
    Write-Host "Java:      $($result.components.jdk.status) $($result.components.jdk.version)"
    Write-Host "IDEA:      $($result.components.idea.status) $($result.components.idea.version)"
    Write-Host "JAVA_HOME: $($result.components.javaHome.status) $($result.components.javaHome.path)"
    Write-Host "结果文件:  $resultPath"
    Write-Log -Level "完成" -Message "检测完成"

    if ($env:JAVA_SETUP_NO_UI -eq "1") {
        Write-Log -Level "信息" -Message "已禁用界面回跳，结果文件可直接上传。"
    } else {
        try {
            $json = $result | ConvertTo-Json -Depth 12 -Compress
            $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
            if ($base64.Length -lt 90000) {
                $bridge = Start-RepairBridge -DetectionResult $result
                $hash = "result=$base64"
                if ($bridge) {
                    $hash += "&bridgePort=$($bridge.port)&bridgeToken=$($bridge.token)"
                    Write-Log -Level "信息" -Message "本地一键修复助手已启动，端口 $($bridge.port)。"
                }
                Start-Process ($OpenPage + "#" + $hash) | Out-Null
            } else {
                Write-Log -Level "提醒" -Message "结果过长，请把 JSON 文件拖到网页中。"
            }
        } catch {
            Write-Log -Level "提醒" -Message "无法自动打开网页，请手动上传检测结果。"
        }
    }

    if ($result.summary.errors -gt 0) { return 10 }
    if ($result.summary.warnings -gt 0) { return 20 }
    return 0
}

function Resolve-TemurinPackage {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $lines = & winget.exe search "EclipseAdoptium.Temurin" --source winget --accept-source-agreements 2>&1
        $packageMatches = foreach ($line in $lines) {
            $match = [regex]::Match([string]$line, "(EclipseAdoptium\.Temurin\.(\d+)\.JDK)\s+([0-9][^\s]*)")
            if ($match.Success) {
                [pscustomobject]@{
                    id = $match.Groups[1].Value
                    major = [int]$match.Groups[2].Value
                    version = $match.Groups[3].Value
                }
            }
        }
        $lts = @(8, 11, 17, 21, 25, 29, 33)
        $candidate = $packageMatches |
            Where-Object { $_.major -ge $script:JdkTargetVersion -and $_.major -in $lts } |
            Sort-Object major, version -Descending |
            Select-Object -First 1
        return $candidate
    } catch {
        return $null
    }
}

function Invoke-PrivilegedProcess {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    if (Test-IsAdmin) {
        & $FilePath @Arguments
        return $LASTEXITCODE
    }

    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }
    $process = Start-Process -FilePath $FilePath -ArgumentList ($quoted -join " ") -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-VerifiedFile {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$ChecksumUri,

        [string]$ExpectedChecksum
    )

    if ([Uri]$Uri -isnot [Uri] -or ([Uri]$Uri).Scheme -ne "https") {
        throw "拒绝下载非 HTTPS 安装包"
    }
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination -TimeoutSec 300
    $expected = $ExpectedChecksum
    if (-not $expected -and $ChecksumUri) {
        if ([Uri]$ChecksumUri -isnot [Uri] -or ([Uri]$ChecksumUri).Scheme -ne "https") {
            throw "拒绝访问非 HTTPS 校验地址"
        }
        $checksumText = (Invoke-WebRequest -UseBasicParsing -Uri $ChecksumUri -TimeoutSec 30).Content
        $expected = ([regex]::Match($checksumText, "[a-fA-F0-9]{64,128}")).Value
    }
    if (-not $expected) {
        throw "无法取得官方 SHA-256 校验值"
    }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    $normalizedExpected = ([regex]::Match($expected, "[a-fA-F0-9]{64}").Value).ToUpperInvariant()
    if (-not $normalizedExpected -or $actual.ToUpperInvariant() -ne $normalizedExpected) {
        throw "安装包 SHA-256 校验失败"
    }
}

function Install-JdkOfficial {
    $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $uri = "https://api.adoptium.net/v3/assets/latest/$script:JdkTargetVersion/hotspot?architecture=$architecture&image_type=jdk&os=windows&vendor=eclipse"
    $response = Invoke-RestMethod -Uri $uri -TimeoutSec 30
    $asset = @($response)[0].binary.package
    if (-not $asset.link -or -not $asset.checksum) {
        throw "Adoptium 官方接口没有返回可用的 JDK 安装包"
    }
    $installer = Join-Path $env:TEMP ("temurin-{0}.msi" -f $script:JdkTargetVersion)
    Get-VerifiedFile -Uri $asset.link -Destination $installer -ExpectedChecksum $asset.checksum
    $exitCode = Invoke-PrivilegedProcess -FilePath "msiexec.exe" -Arguments @("/i", $installer, "/qn", "/norestart", "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJavaHome")
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    if ($exitCode -ne 0) {
        throw "JDK 安装程序返回错误码 $exitCode"
    }
}

function Install-Jdk {
    $package = Resolve-TemurinPackage
    if ($package) {
        Write-Log -Level "信息" -Message "从 winget 动态选择包：$($package.id) $($package.version)"
        $exitCode = Invoke-PrivilegedProcess -FilePath "winget.exe" -Arguments @(
            "install", "--id", $package.id, "-e", "--silent",
            "--accept-package-agreements", "--accept-source-agreements",
            "--disable-interactivity"
        )
        if ($exitCode -in @(0, -1978335189)) {
            return
        }
        Write-Log -Level "提醒" -Message "winget 安装未成功，改用 Adoptium 官方安装包。"
    } else {
        Write-Log -Level "提醒" -Message "未查询到 JDK $script:JdkTargetVersion 的 winget 包，改用 Adoptium 官方安装包。"
    }
    Install-JdkOfficial
}

function Install-IdeaOfficial {
    param([object]$LatestIdea)

    if (-not $LatestIdea.windowsUrl) {
        throw "无法取得 JetBrains 官方 IDEA 下载地址"
    }
    $installer = Join-Path $env:TEMP "idea-community.exe"
    Get-VerifiedFile -Uri $LatestIdea.windowsUrl -Destination $installer -ChecksumUri $LatestIdea.checksum
    $exitCode = Invoke-PrivilegedProcess -FilePath $installer -Arguments @("/S")
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    if ($exitCode -ne 0) {
        throw "IDEA 安装程序返回错误码 $exitCode"
    }
}

function Install-Idea {
    $ideas = Get-IdeaInstallations
    $latest = Get-LatestIdeaRelease
    $selected = $ideas | Sort-Object { Get-PeVersion $_.version } -Descending | Select-Object -First 1

    if ($selected -and $latest.status -eq "ok" -and (Compare-VersionValue $selected.version $latest.version) -ge 0) {
        return
    }

    if (-not $selected -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        $exitCode = Invoke-PrivilegedProcess -FilePath "winget.exe" -Arguments @(
            "install", "--id", "JetBrains.IntelliJIDEA.Community", "-e", "--silent",
            "--accept-package-agreements", "--accept-source-agreements",
            "--disable-interactivity"
        )
        if ($exitCode -in @(0, -1978335189)) {
            $installed = Get-IdeaInstallations | Sort-Object { Get-PeVersion $_.version } -Descending | Select-Object -First 1
            if ($installed -and $latest.status -eq "ok" -and (Compare-VersionValue $installed.version $latest.version) -ge 0) {
                return
            }
        }
    }
    Install-IdeaOfficial -LatestIdea $latest
}

function Set-JavaEnvironment {
    param([object]$Jdk)

    if (-not $Jdk) {
        throw "没有可用 JDK，无法配置 JAVA_HOME"
    }
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $Jdk.path, "User")
    $env:JAVA_HOME = $Jdk.path

    $bin = Join-Path $Jdk.path "bin"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($userPath -split ";" | Where-Object { $_ -and $_.Trim() })
    $filtered = foreach ($entry in $entries) {
        try {
            if ([System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($entry)).TrimEnd("\") -ine [System.IO.Path]::GetFullPath($bin).TrimEnd("\")) {
                $entry
            }
        } catch {
            $entry
        }
    }
    $newPath = (@($bin) + @($filtered) | Select-Object -Unique) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$bin;$env:Path"
    Write-Log -Level "完成" -Message "已设置用户级 JAVA_HOME 和 PATH"
}

function Invoke-SmokeTest {
    $temp = Join-Path $env:TEMP ("java-setup-smoke-{0}" -f [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    try {
        $source = Join-Path $temp "HelloWorld.java"
        @"
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello World");
    }
}
"@ | Set-Content -LiteralPath $source -Encoding UTF8
        $compileOutput = & javac $source 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "javac 编译失败：$compileOutput"
        }
        $runOutput = & java -cp $temp HelloWorld 2>&1
        if ($LASTEXITCODE -ne 0 -or ($runOutput | Out-String).Trim() -ne "Hello World") {
            throw "Hello World 运行结果不正确：$runOutput"
        }
        Write-Log -Level "完成" -Message "Hello World 编译和运行验证通过"
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-VCRuntime {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            $runtime = Get-ItemProperty $path -ErrorAction SilentlyContinue
            if ($runtime.Installed -eq 1) {
                return $true
            }
        }
    }
    return $false
}

function Test-IdeaHealthy {
    $idea = Get-IdeaInstallations |
        Sort-Object { Get-PeVersion $_.version } -Descending |
        Select-Object -First 1
    if (-not $idea -or -not $idea.path) {
        return $false
    }
    $executables = @(
        (Join-Path $idea.path "bin\idea64.exe"),
        (Join-Path $idea.path "bin\idea.exe")
    )
    foreach ($executable in $executables) {
        if (Test-Path -LiteralPath $executable -PathType Leaf) {
            try {
                & $executable --version *> $null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
    }
    return $false
}

function Invoke-PlatformFixes {
    if (-not (Test-VCRuntime)) {
        Write-Log -Level "信息" -Message "正在安装 VC++ Runtime"
        $exitCode = Invoke-PrivilegedProcess -FilePath "winget.exe" -Arguments @(
            "install", "--id", "Microsoft.VCRedist.2015+.x64", "-e", "--silent",
            "--accept-package-agreements", "--accept-source-agreements",
            "--disable-interactivity"
        )
        if ($exitCode -notin @(0, -1978335189)) {
            throw "VC++ Runtime 安装失败，退出码 $exitCode"
        }
    } else {
        Write-Log -Level "完成" -Message "VC++ Runtime 已安装"
    }

    if (-not (Test-IdeaHealthy)) {
        Write-Log -Level "提醒" -Message "检测到 IDEA 可能损坏，正在重新安装。"
        Uninstall-ByName -DisplayNamePattern "(?i)IntelliJ IDEA Community" | Out-Null
        Install-Idea
    }
}

function Invoke-Install {
    param([switch]$FixAll)

    if ($Resume) {
        Write-Log -Level "信息" -Message "已启用断点续装：将复用已安装组件。"
    }
    $progressUrl = Open-ProgressPage -ProgressAction "install"
    if ($progressUrl) {
        Write-Log -Level "信息" -Message "已打开本地进度页：$progressUrl"
    }
    Initialize-Progress -ProgressAction "install" -Steps @(
        @{ id = "prepare"; label = "检查系统和网络"; estimatedSeconds = 30 },
        @{ id = "jdk"; label = "安装或确认 JDK 25"; estimatedSeconds = 120 },
        @{ id = "idea"; label = "安装最新版 IntelliJ IDEA Community"; estimatedSeconds = 180 },
        @{ id = "verify"; label = "配置环境并运行 Hello World"; estimatedSeconds = 40 }
    )

    try {
        Set-ProgressStep -Index 0 -Status "running" -Message "正在检查系统环境"
        Invoke-Detection | Out-Null
        Set-ProgressStep -Index 0 -Status "complete" -Message "环境和网络检查完成"

        if ($DryRun) {
            Write-Log -Level "信息" -Message "dry-run：不会执行真实安装。"
            $plannedPackage = Resolve-TemurinPackage
            if ($plannedPackage) {
                Write-Log -Level "信息" -Message "dry-run：动态选择 JDK 包 $($plannedPackage.id) $($plannedPackage.version)"
            } else {
                Write-Log -Level "信息" -Message "dry-run：未找到 JDK 包，真实安装时会回退 Adoptium 官方包。"
            }
            $plannedIdea = Get-LatestIdeaRelease
            if ($plannedIdea.status -eq "ok") {
                Write-Log -Level "信息" -Message "dry-run：IDEA 官方最新版为 $($plannedIdea.version)"
            } else {
                Write-Log -Level "提醒" -Message "dry-run：无法确认 IDEA 最新版。"
            }
            Set-ProgressStep -Index 1 -Status "complete" -Message "dry-run 跳过 JDK 安装"
            Set-ProgressStep -Index 2 -Status "complete" -Message "dry-run 跳过 IDEA 安装"
            Set-ProgressStep -Index 3 -Status "complete" -Message "dry-run 跳过环境写入"
            $result = New-DetectionResult -Candidates (Get-JavaCandidates) -Ideas (Get-IdeaInstallations) -LatestIdea (Get-LatestIdeaRelease) -Network (Get-NetworkStatus)
            Write-ProgressState -Status "success" -CurrentStep 4 -Percent 100 -Message "dry-run 已完成" -Result $result
            return 0
        }

        Set-ProgressStep -Index 1 -Status "running" -Message "正在检测并准备 JDK $script:JdkTargetVersion"
        $candidates = Get-JavaCandidates
        $selected = Select-JavaHome -Candidates $candidates
        if (-not $selected -or $selected.major -lt $script:JdkTargetVersion) {
            Install-Jdk
            $candidates = Get-JavaCandidates
            $selected = Select-JavaHome -Candidates $candidates
        }
        if (-not $selected -or $selected.major -lt $script:JdkTargetVersion) {
            throw "JDK 安装后仍未检测到满足要求的版本"
        }
        Write-Log -Level "完成" -Message "JDK $($selected.version) 已就绪"
        Set-ProgressStep -Index 1 -Status "complete" -Message "JDK $($selected.version)"

        Set-ProgressStep -Index 2 -Status "running" -Message "正在安装或升级 IntelliJ IDEA Community"
        Install-Idea
        $idea = Get-IdeaInstallations | Sort-Object { Get-PeVersion $_.version } -Descending | Select-Object -First 1
        if (-not $idea) {
            throw "IDEA 安装后仍未检测到应用"
        }
        Write-Log -Level "完成" -Message "IDEA $($idea.version) 已就绪"
        Set-ProgressStep -Index 2 -Status "complete" -Message "IDEA $($idea.version)"

        Set-ProgressStep -Index 3 -Status "running" -Message "正在配置环境并执行冒烟测试"
        $selected = Select-JavaHome -Candidates (Get-JavaCandidates)
        Set-JavaEnvironment -Jdk $selected
        if ($FixAll) {
            Invoke-PlatformFixes
        }
        Invoke-SmokeTest
        Set-ProgressStep -Index 3 -Status "complete" -Message "环境配置和 Hello World 验证完成"

        $result = Invoke-Detection
        Write-ProgressState -Status "success" -CurrentStep 4 -Percent 100 -Message "Java 和 IDEA 已安装并验证完成" -Result $result
        return 0
    } catch {
        Write-Log -Level "错误" -Message $_.Exception.Message
        $failedIndex = 0
        for ($index = 0; $index -lt $script:ProgressSteps.Count; $index++) {
            if ($script:ProgressSteps[$index].status -eq "running") {
                $failedIndex = $index
                Set-ProgressStep -Index $index -Status "failed" -Message $_.Exception.Message
                break
            }
        }
        Write-ProgressState -Status "failed" -CurrentStep $failedIndex -Percent ([Math]::Round(($failedIndex / [Math]::Max(1, $script:ProgressSteps.Count)) * 100)) -Message $_.Exception.Message
        return 1
    }
}

function Invoke-Fix {
    $progressUrl = Open-ProgressPage -ProgressAction "fix"
    if ($progressUrl) {
        Write-Log -Level "信息" -Message "已打开本地进度页：$progressUrl"
    }
    Initialize-Progress -ProgressAction "fix" -Steps @(
        @{ id = $Fix; label = "修复 $Fix"; estimatedSeconds = 60 }
    )
    try {
        Set-ProgressStep -Index 0 -Status "running" -Message "正在执行修复"
        switch ($Fix) {
            "java_home" {
                $jdk = Select-JavaHome -Candidates (Get-JavaCandidates)
                Set-JavaEnvironment -Jdk $jdk
            }
            "path" {
                $jdk = Select-JavaHome -Candidates (Get-JavaCandidates)
                Set-JavaEnvironment -Jdk $jdk
            }
            "multiple_jdks" {
                $jdk = Select-JavaHome -Candidates (Get-JavaCandidates)
                Set-JavaEnvironment -Jdk $jdk
            }
            "idea_repair" {
                Install-Idea
            }
            "vc_runtime" {
                $exitCode = Invoke-PrivilegedProcess -FilePath "winget.exe" -Arguments @(
                    "install", "--id", "Microsoft.VCRedist.2015+.x64", "-e", "--silent",
                    "--accept-package-agreements", "--accept-source-agreements",
                    "--disable-interactivity"
                )
                if ($exitCode -notin @(0, -1978335189)) {
                    throw "VC++ Runtime 安装失败，退出码 $exitCode"
                }
            }
            "port" {
                $used = @(8080, 8081, 8000, 3000, 63342 | Where-Object {
                        Get-NetTCPConnection -State Listen -LocalPort $_ -ErrorAction SilentlyContinue
                    })
                if ($used.Count -gt 0) {
                    Write-Log -Level "提醒" -Message "端口被占用：$($used -join ', ')。请使用 8081、3000 或让 IDE 自动选择。"
                } else {
                    Write-Log -Level "完成" -Message "常用开发端口当前可用"
                }
            }
        }
        Set-ProgressStep -Index 0 -Status "complete" -Message "修复步骤完成"
        $result = Invoke-Detection
        Write-ProgressState -Status "success" -CurrentStep 1 -Percent 100 -Message "修复完成" -Result $result
        return 0
    } catch {
        Write-Log -Level "错误" -Message $_.Exception.Message
        Set-ProgressStep -Index 0 -Status "failed" -Message $_.Exception.Message
        Write-ProgressState -Status "failed" -CurrentStep 0 -Percent 40 -Message $_.Exception.Message
        return 1
    }
}

function Remove-JetBrainsUserData {
    $targets = @(
        (Join-Path $env:APPDATA "JetBrains"),
        (Join-Path $env:LOCALAPPDATA "JetBrains")
    )
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) {
            Get-ChildItem -LiteralPath $target -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "(?i)IntelliJIdea" } |
                ForEach-Object {
                    Write-Log -Level "信息" -Message "清理配置：$($_.FullName)"
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force
                }
        }
    }
}

function Uninstall-ByName {
    param([string]$DisplayNamePattern)
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        return $false
    }
    $lines = & winget.exe list --accept-source-agreements 2>&1
    $entry = $lines | Where-Object { [string]$_ -match $DisplayNamePattern } | Select-Object -First 1
    if (-not $entry) {
        return $false
    }
    $match = [regex]::Match([string]$entry, "([A-Za-z0-9._-]+\.[A-Za-z0-9._-]+)")
    if (-not $match.Success) {
        return $false
    }
    $exitCode = Invoke-PrivilegedProcess -FilePath "winget.exe" -Arguments @(
        "uninstall", "--id", $match.Groups[1].Value, "-e", "--silent",
        "--accept-source-agreements", "--disable-interactivity"
    )
    return $exitCode -in @(0, -1978335212)
}

function Invoke-Uninstall {
    Write-Log -Level "提醒" -Message "默认卸载会删除 IDEA、目标 JDK、JetBrains 设置、缓存、插件和最近项目历史。"
    Write-Log -Level "提醒" -Message "不会删除你的 Java 项目源码目录。"
    if (-not $KeepSettings) {
        $answer = Read-Host "确认彻底清理请输入 DELETE"
        if ($answer -cne "DELETE") {
            Write-Log -Level "信息" -Message "已取消卸载。"
            return 0
        }
    }

    $progressUrl = Open-ProgressPage -ProgressAction "uninstall"
    if ($progressUrl) {
        Write-Log -Level "信息" -Message "已打开本地进度页：$progressUrl"
    }
    Initialize-Progress -ProgressAction "uninstall" -Steps @(
        @{ id = "detect"; label = "检测已安装组件"; estimatedSeconds = 20 },
        @{ id = "idea"; label = "卸载 IntelliJ IDEA Community"; estimatedSeconds = 60 },
        @{ id = "jdk"; label = "卸载目标 JDK"; estimatedSeconds = 60 },
        @{ id = "clean"; label = "清理环境变量与配置"; estimatedSeconds = 30 }
    )

    try {
        Set-ProgressStep -Index 0 -Status "running" -Message "正在检测已安装组件"
        $candidates = Get-JavaCandidates
        $jdk = Select-JavaHome -Candidates $candidates
        Set-ProgressStep -Index 0 -Status "complete" -Message "检测完成"

        Set-ProgressStep -Index 1 -Status "running" -Message "正在卸载 IDEA"
        if (-not (Uninstall-ByName -DisplayNamePattern "(?i)IntelliJ IDEA Community")) {
            Write-Log -Level "提醒" -Message "winget 未找到 IDEA；如果它是手动安装的，请从设置中的应用列表卸载。"
        }
        Set-ProgressStep -Index 1 -Status "complete" -Message "IDEA 处理完成"

        Set-ProgressStep -Index 2 -Status "running" -Message "正在卸载 JDK $script:JdkTargetVersion"
        if (-not (Uninstall-ByName -DisplayNamePattern "Eclipse Temurin JDK.*$script:JdkTargetVersion")) {
            Write-Log -Level "提醒" -Message "未通过 winget 找到目标 JDK，保留现有 JDK 安装目录。"
        }
        Set-ProgressStep -Index 2 -Status "complete" -Message "JDK 处理完成"

        Set-ProgressStep -Index 3 -Status "running" -Message "正在清理用户环境变量"
        if ($jdk -and (Test-Path -LiteralPath $jdk.path)) {
            if ($env:JAVA_HOME -and ([System.IO.Path]::GetFullPath($env:JAVA_HOME) -ieq [System.IO.Path]::GetFullPath($jdk.path))) {
                [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, "User")
            }
            $bin = [System.IO.Path]::GetFullPath((Join-Path $jdk.path "bin")).TrimEnd("\")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $newEntries = @($userPath -split ";" | Where-Object {
                    if (-not $_) { return $false }
                    try {
                        [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($_)).TrimEnd("\") -ine $bin
                    } catch {
                        $true
                    }
                })
            [Environment]::SetEnvironmentVariable("Path", ($newEntries -join ";"), "User")
        } else {
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, "User")
        }
        if (-not $KeepSettings) {
            Remove-JetBrainsUserData
        }
        Set-ProgressStep -Index 3 -Status "complete" -Message "清理完成"

        $result = [ordered]@{
            schemaVersion = 1
            action = "uninstall"
            generatedAt = Get-Timestamp
            status = "success"
            message = if ($KeepSettings) { "程序和目标 JDK 已处理，设置目录已保留" } else { "程序、目标 JDK 和 JetBrains 用户配置已清理" }
        }
        Write-ProgressState -Status "success" -CurrentStep 4 -Percent 100 -Message "卸载和清理完成" -Result $result
        return 0
    } catch {
        Write-Log -Level "错误" -Message $_.Exception.Message
        Write-ProgressState -Status "failed" -CurrentStep 0 -Percent 30 -Message $_.Exception.Message
        return 1
    }
}

try {
    switch ($Action) {
        "detect" { exit (Invoke-Detection) }
        "install" {
            if ($FixAll) {
                exit (Invoke-Install -FixAll)
            }
            if ($Fix) {
                exit (Invoke-Fix)
            }
            exit (Invoke-Install)
        }
        "uninstall" { exit (Invoke-Uninstall) }
        "verify" {
            Set-JavaEnvironment -Jdk (Select-JavaHome -Candidates (Get-JavaCandidates))
            Invoke-SmokeTest
            exit 0
        }
    }
} catch {
    Write-Host "[错误] $($_.Exception.Message)" -ForegroundColor Red
    if ($env:JAVA_SETUP_DEBUG -eq "1") {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}
