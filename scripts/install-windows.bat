@echo off
setlocal EnableExtensions
title Java + IDEA Setup

set "JAVA_IDEA_INSTALLER=%~f0"
set "JAVA_IDEA_ARGUMENTS=%*"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand JABzAG8AdQByAGMAZQA9AEcAZQB0AC0AQwBvAG4AdABlAG4AdAAgAC0ATABpAHQAZQByAGEAbABQAGEAdABoACAAJABlAG4AdgA6AEoAQQBWAEEAXwBJAEQARQBBAF8ASQBOAFMAVABBAEwATABFAFIAIAAtAFIAYQB3AAoAJABtAGEAcgBrAGUAcgA9ACcAIwAgAFAATwBXAEUAUgBTAEgARQBMAEwAXwBCAEUARwBJAE4AJwAKACQAaQBuAGQAZQB4AD0AJABzAG8AdQByAGMAZQAuAEwAYQBzAHQASQBuAGQAZQB4AE8AZgAoACQAbQBhAHIAawBlAHIALABbAFMAdAByAGkAbgBnAEMAbwBtAHAAYQByAGkAcwBvAG4AXQA6ADoATwByAGQAaQBuAGEAbAApAAoAaQBmACgAJABpAG4AZABlAHgAIAAtAGwAdAAgADAAKQB7AHQAaAByAG8AdwAgACcAUABvAHcAZQByAFMAaABlAGwAbAAgAHAAYQB5AGwAbwBhAGQAIABtAGEAcgBrAGUAcgAgAGkAcwAgAG0AaQBzAHMAaQBuAGcALgAnAH0ACgAkAHMAYwByAGkAcAB0AFQAZQB4AHQAPQAkAHMAbwB1AHIAYwBlAC4AUwB1AGIAcwB0AHIAaQBuAGcAKAAkAGkAbgBkAGUAeAArACQAbQBhAHIAawBlAHIALgBMAGUAbgBnAHQAaAApAAoAJABhAHIAZwB1AG0AZQBuAHQAcwA9AEAAKAApAAoAaQBmACgAJABlAG4AdgA6AEoAQQBWAEEAXwBJAEQARQBBAF8AQQBSAEcAVQBNAEUATgBUAFMAKQB7ACQAYQByAGcAdQBtAGUAbgB0AHMAPQBAACgAJABlAG4AdgA6AEoAQQBWAEEAXwBJAEQARQBBAF8AQQBSAEcAVQBNAEUATgBUAFMAIAAtAHMAcABsAGkAdAAgACcAXABzACsAJwApAH0ACgAmACAAKABbAHMAYwByAGkAcAB0AGIAbABvAGMAawBdADoAOgBDAHIAZQBhAHQAZQAoACQAcwBjAHIAaQBwAHQAVABlAHgAdAApACkAIABAAGEAcgBnAHUAbQBlAG4AdABzAA==
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" if not "%EXIT_CODE%"=="2" pause
exit /b %EXIT_CODE%
goto :eof

# POWERSHELL_BEGIN
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$DryRun = @($args) -contains "--dry-run"
$IgnoreExisting = @($args) -contains "--ignore-existing"
$NoLaunch = @($args) -contains "--no-launch"
$JdkMajorVersion = 25
$FallbackJavaVersion = "25.0.4.1+1"
$FallbackJavaInstallerName = "OpenJDK25U-jdk_x64_windows_hotspot_25.0.4.1_1.msi"
$FallbackJavaSha256 = "517b3590be43120c34c3891d09c97a1eddc12da982208c4f5adf1bdc1b5e3f15"
$FallbackJavaReleaseTag = "jdk-25.0.4.1%2B1"
$IdeaVersion = "2025.2.6.2"
$IdeaInstallerName = "ideaIC-$IdeaVersion.exe"
$IdeaUris = @(
    "https://download-cdn.jetbrains.com/idea/$IdeaInstallerName",
    "https://download.jetbrains.com/idea/$IdeaInstallerName"
)
$IdeaChecksumUri = "https://download.jetbrains.com/idea/$IdeaInstallerName.sha256"
$FallbackIdeaSha256 = "8393c2c9ccbd8581d646f01f0b6f0e7f78e58ebbe5cd8cbd95f9e236518e9fe8"
$MinimumFreeBytes = 6GB
$MaximumAttempts = 4
$Headers = @{ "User-Agent" = "JavaIdeaMinimalInstaller/1.0" }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Line {
    param(
        [string]$Message = "",
        [ConsoleColor]$Color
    )

    $previousColor = [Console]::ForegroundColor
    try {
        if ($PSBoundParameters.ContainsKey("Color")) {
            [Console]::ForegroundColor = $Color
        }
        [Console]::WriteLine($Message)
    } finally {
        [Console]::ForegroundColor = $previousColor
    }
}

function Write-Section {
    param([string]$Message)

    Write-Line
    Write-Line -Message "== $Message ==" -Color Cyan
}

function Format-Size {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return ("{0:N1} GB" -f ($Bytes / 1GB))
    }
    if ($Bytes -ge 1MB) {
        return ("{0:N0} MB" -f ($Bytes / 1MB))
    }
    return ("{0:N0} KB" -f ($Bytes / 1KB))
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [Parameter(Mandatory)]
        [string]$Label,

        [int]$Attempts = $MaximumAttempts
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Write-Line "[INFO] $Label (attempt $attempt/$Attempts)"
            return & $Operation
        } catch {
            if ($attempt -eq $Attempts) {
                throw "$Label failed after $Attempts attempts: $($_.Exception.Message)"
            }
            Start-Sleep -Seconds $attempt
        }
    }
}

function Get-Sha256 {
    param([string]$Path)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
}

function Get-RemoteText {
    param(
        [string]$Uri,
        [string]$Label
    )

    return Invoke-WithRetry -Label $Label -Operation {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers $Headers -TimeoutSec 30
        return [string]$response.Content
    }
}

function Get-VerifiedFile {
    param(
        [string[]]$Uri,
        [string]$Destination,
        [string]$ExpectedSha256,
        [string]$Label
    )

    $sources = @($Uri | Where-Object { $_ } | Select-Object -Unique)
    $failures = New-Object System.Collections.Generic.List[string]
    $expected = $ExpectedSha256.ToLowerInvariant()

    foreach ($source in $sources) {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        }

        try {
            Invoke-WithRetry -Label "$Label from $source" -Operation {
                if (Test-Path -LiteralPath $Destination) {
                    Remove-Item -LiteralPath $Destination -Force
                }

                try {
                    Invoke-WebRequest -UseBasicParsing -Uri $source -Headers $Headers -OutFile $Destination -TimeoutSec 900
                } catch {
                    $webRequestError = $_
                    if (-not (Get-Command "curl.exe" -ErrorAction SilentlyContinue)) {
                        throw
                    }

                    Write-Line "[INFO] PowerShell download failed, retrying with curl.exe."
                    & curl.exe `
                        --fail `
                        --location `
                        --silent `
                        --show-error `
                        --retry 3 `
                        --retry-delay 2 `
                        --connect-timeout 30 `
                        --output $Destination `
                        $source
                    if ($LASTEXITCODE -ne 0) {
                        throw "PowerShell and curl downloads failed. PowerShell error: $($webRequestError.Exception.Message)"
                    }
                }
            } | Out-Null
        } catch {
            if (Test-Path -LiteralPath $Destination) {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            }
            $failures.Add("$source : $($_.Exception.Message)")
            Write-Line -Message "[WARN] Download source failed: $source" -Color Yellow
            continue
        }

        $actual = Get-Sha256 -Path $Destination
        if ($actual -ne $expected) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            $failures.Add("$source : SHA-256 mismatch. Expected $expected, got $actual")
            Write-Line -Message "[WARN] SHA-256 mismatch from $source. Trying the next source." -Color Yellow
            continue
        }

        return $Destination
    }

    throw "$Label failed from all sources. $($failures -join ' | ')"
}

function Normalize-JavaHome {
    param([string]$Path)

    if (-not $Path) {
        return $null
    }

    $normalized = $Path.Trim().Trim('"').TrimEnd("\")
    if ([IO.Path]::GetFileName($normalized) -ieq "bin") {
        $normalized = Split-Path -Parent $normalized
    }
    return $normalized
}

function Get-JavaInstallationFromHome {
    param([string]$JdkPath)

    $normalized = Normalize-JavaHome -Path $JdkPath
    if (-not $normalized) {
        return $null
    }

    $javaExe = Join-Path $normalized "bin\java.exe"
    $javacExe = Join-Path $normalized "bin\javac.exe"
    if (-not (Test-Path -LiteralPath $javaExe -PathType Leaf) -or
        -not (Test-Path -LiteralPath $javacExe -PathType Leaf)) {
        return $null
    }

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $versionOutput = & $javaExe -version 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($exitCode -ne 0 -or $versionOutput -notmatch 'version "(?<version>\d+(?:\.\d+)*)"') {
        return $null
    }

    $version = $Matches.version
    $majorVersion = [int]($version -split '\.')[0]
    if ($majorVersion -ne $JdkMajorVersion) {
        return $null
    }

    return [pscustomobject]@{
        Name = "Eclipse Temurin JDK $version"
        Home = $normalized
        Version = $version
    }
}

function Get-ExistingJavaInstallation {
    $candidates = New-Object System.Collections.Generic.List[string]
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "Eclipse Temurin JDK.*$JdkMajorVersion" } |
        ForEach-Object { $candidates.Add([string]$_.InstallLocation) }

    @(
        $env:JAVA_HOME,
        [Environment]::GetEnvironmentVariable("JAVA_HOME", "User"),
        [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine"),
        (Join-Path $env:USERPROFILE "JavaDev\jdk-$JdkMajorVersion")
    ) | ForEach-Object { $candidates.Add([string]$_) }

    @(
        (Join-Path $env:ProgramFiles "Eclipse Adoptium"),
        (Join-Path $env:ProgramFiles "Java"),
        (Join-Path ${env:ProgramFiles(x86)} "Eclipse Adoptium"),
        (Join-Path ${env:ProgramFiles(x86)} "Java")
    ) | ForEach-Object {
        if (Test-Path -LiteralPath $_) {
            Get-ChildItem -LiteralPath $_ -Directory -Filter "jdk-$JdkMajorVersion*" -ErrorAction SilentlyContinue |
                ForEach-Object { $candidates.Add($_.FullName) }
        }
    }

    foreach ($candidate in @($candidates | Where-Object { $_ } | Sort-Object -Unique)) {
        $installation = Get-JavaInstallationFromHome -JdkPath $candidate
        if ($installation) {
            return $installation
        }
    }

    return $null
}

function Get-IdeaInstallationFromHome {
    param([string]$IdeaPath)

    if (-not $IdeaPath) {
        return $null
    }

    $normalized = $IdeaPath.Trim().Trim('"').TrimEnd("\")
    if ([IO.Path]::GetFileName($normalized) -ieq "idea64.exe") {
        $normalized = Split-Path -Parent (Split-Path -Parent $normalized)
    } elseif ([IO.Path]::GetFileName($normalized) -ieq "bin") {
        $normalized = Split-Path -Parent $normalized
    }

    $ideaExe = Join-Path $normalized "bin\idea64.exe"
    $productInfoPath = Join-Path $normalized "product-info.json"
    if (-not (Test-Path -LiteralPath $ideaExe -PathType Leaf) -or
        -not (Test-Path -LiteralPath $productInfoPath -PathType Leaf)) {
        return $null
    }

    try {
        $productInfo = Get-Content -LiteralPath $productInfoPath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }

    $version = [string]$productInfo.version
    if ($version -ine $IdeaVersion) {
        return $null
    }

    return [pscustomobject]@{
        Name = "IntelliJ IDEA Community $version"
        Home = $normalized
        Version = $version
    }
}

function Get-ExistingIdeaInstallation {
    $candidates = New-Object System.Collections.Generic.List[string]
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "IntelliJ IDEA Community Edition" } |
        ForEach-Object { $candidates.Add([string]$_.InstallLocation) }

    @(
        (Join-Path $env:ProgramFiles "JetBrains\IntelliJ IDEA Community Edition $IdeaVersion"),
        (Join-Path $env:LOCALAPPDATA "Programs\IntelliJ IDEA Community Edition $IdeaVersion"),
        (Join-Path $env:USERPROFILE "JavaDev\idea-$IdeaVersion")
    ) | ForEach-Object { $candidates.Add([string]$_) }

    if (Test-Path -LiteralPath (Join-Path $env:ProgramFiles "JetBrains")) {
        Get-ChildItem -LiteralPath (Join-Path $env:ProgramFiles "JetBrains") -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "IntelliJ IDEA Community Edition" } |
            ForEach-Object { $candidates.Add($_.FullName) }
    }

    foreach ($candidate in @($candidates | Where-Object { $_ } | Sort-Object -Unique)) {
        $installation = Get-IdeaInstallationFromHome -IdeaPath $candidate
        if ($installation) {
            return $installation
        }
    }

    return $null
}

function Set-JavaEnvironment {
    param([string]$JdkHome)

    $normalized = Normalize-JavaHome -Path $JdkHome
    $javaBin = Join-Path $normalized "bin"
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $normalized, "User")
    $env:JAVA_HOME = $normalized

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $effectivePath = @($machinePath, $userPath) -join ";"
    $hasJavaBin = @($effectivePath -split ";" | Where-Object {
        $_.Trim().TrimEnd("\") -ieq $javaBin.TrimEnd("\")
    }).Count -gt 0

    if (-not $hasJavaBin) {
        $pathParts = @($userPath, $javaBin) |
            Where-Object { $_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            ForEach-Object { $_.TrimEnd(";") }
        $newUserPath = $pathParts -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    }

    $currentPathEntries = @($env:Path -split ";" | Where-Object {
        $_.Trim().TrimEnd("\") -ieq $javaBin.TrimEnd("\")
    })
    if ($currentPathEntries.Count -eq 0) {
        $env:Path = "$javaBin;$env:Path"
    }
}

function Get-FixedDriveChoices {
    $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        ForEach-Object {
            [pscustomobject]@{
                DeviceId = [string]$_.DeviceID
                Label = [string]$_.VolumeName
                FreeSpace = [long]$_.FreeSpace
                Size = [long]$_.Size
            }
        } |
        Where-Object { $_.FreeSpace -ge $MinimumFreeBytes } |
        Sort-Object DeviceId

    return @($drives)
}

function Select-InstallDrive {
    param([array]$Drives)

    if ($Drives.Count -eq 0) {
        throw "No fixed disk has at least 6 GB of free space."
    }

    if ($DryRun) {
        return $Drives[0]
    }

    while ($true) {
        Write-Section "Choose installation drive"
        for ($index = 0; $index -lt $Drives.Count; $index++) {
            $drive = $Drives[$index]
            $name = if ($drive.Label) { " ($($drive.Label))" } else { "" }
            Write-Line ("[{0}] {1}{2} - {3} free" -f ($index + 1), $drive.DeviceId, $name, (Format-Size $drive.FreeSpace))
        }

        $answer = (Read-Host "Enter drive letter (for example D)").Trim().TrimEnd(":")
        $selected = $Drives | Where-Object { $_.DeviceId.TrimEnd(":") -ieq $answer } | Select-Object -First 1
        if ($selected) {
            return $selected
        }

        Write-Line -Message "[WARN] Invalid drive. Choose one of the listed letters." -Color Yellow
    }
}

function Get-InstallRoot {
    param([string]$DriveLetter)

    if ($DriveLetter.TrimEnd(":") -ieq "C") {
        return Join-Path $env:USERPROFILE "JavaDev"
    }

    return Join-Path ($DriveLetter.TrimEnd("\") + "\") "JavaDev"
}

function New-JavaPackage {
    param(
        [string]$Version,
        [string]$InstallerName,
        [string]$OfficialUri,
        [string]$Sha256,
        [string]$ResolutionSource
    )

    $sources = @(
        "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/$JdkMajorVersion/jdk/x64/windows/$InstallerName",
        "https://mirrors.nju.edu.cn/adoptium/$JdkMajorVersion/jdk/x64/windows/$InstallerName",
        $OfficialUri
    ) | Where-Object { $_ } | Select-Object -Unique

    return [pscustomobject]@{
        Version = $Version
        InstallerName = $InstallerName
        SourceUri = $ResolutionSource
        Uri = $OfficialUri
        Uris = @($sources)
        Sha256 = $Sha256.ToLowerInvariant()
    }
}

function Resolve-JavaPackage {
    $uri = "https://api.adoptium.net/v3/assets/latest/$JdkMajorVersion/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse&installer_type=msi"
    try {
        $response = Invoke-WithRetry -Label "Resolve latest JDK $JdkMajorVersion LTS" -Operation {
            return Invoke-RestMethod -Uri $uri -Headers $Headers -TimeoutSec 30
        }

        $asset = @($response)[0]
        $installer = $asset.binary.installer
        if (-not $installer.link -or -not $installer.checksum) {
            throw "Adoptium did not return a Windows MSI package."
        }

        $installerName = if ($installer.name) {
            [string]$installer.name
        } else {
            [IO.Path]::GetFileName(([Uri]$installer.link).AbsolutePath)
        }

        return New-JavaPackage `
            -Version ([string]$asset.version.semver) `
            -InstallerName $installerName `
            -OfficialUri ([string]$installer.link) `
            -Sha256 ([string]$installer.checksum) `
            -ResolutionSource $uri
    } catch {
        Write-Line -Message "[WARN] Adoptium API unavailable: $($_.Exception.Message)" -Color Yellow
        Write-Line "[INFO] Using verified JDK $FallbackJavaVersion fallback."

        $officialUri = "https://github.com/adoptium/temurin25-binaries/releases/download/$FallbackJavaReleaseTag/$FallbackJavaInstallerName"
        return New-JavaPackage `
            -Version $FallbackJavaVersion `
            -InstallerName $FallbackJavaInstallerName `
            -OfficialUri $officialUri `
            -Sha256 $FallbackJavaSha256 `
            -ResolutionSource "verified fallback"
    }
}

function Resolve-IdeaChecksum {
    try {
        $content = Get-RemoteText -Uri $IdeaChecksumUri -Label "Resolve IDEA checksum"
        $match = [regex]::Match($content, "[a-fA-F0-9]{64}")
        if (-not $match.Success) {
            throw "JetBrains checksum file does not contain a SHA-256 value."
        }
        return $match.Value.ToLowerInvariant()
    } catch {
        Write-Line -Message "[WARN] JetBrains checksum unavailable: $($_.Exception.Message)" -Color Yellow
        Write-Line "[INFO] Using verified IDEA checksum fallback."
        return $FallbackIdeaSha256
    }
}

function Ensure-RootDirectory {
    param([string]$Root)

    try {
        New-Item -ItemType Directory -Force -Path $Root | Out-Null
    } catch {
        throw "Cannot create installation directory $Root. Choose another drive or run this file as administrator."
    }
}

function Install-Java {
    param(
        [object]$Package,
        [string]$DownloadDirectory,
        [string]$JdkHome,
        [string]$LogPath
    )

    $installerPath = Join-Path $DownloadDirectory $Package.InstallerName
    Get-VerifiedFile `
        -Uri $Package.Uris `
        -Destination $installerPath `
        -ExpectedSha256 $Package.Sha256 `
        -Label "Download Java $($Package.Version)" | Out-Null

    $arguments = @(
        "/i",
        "`"$installerPath`"",
        "/qn",
        "/norestart",
        "/L*v",
        "`"$LogPath`"",
        "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJavaHome",
        "INSTALLDIR=`"$JdkHome`""
    )

    Write-Line "[INFO] Installing Java with administrator permission."
    try {
        $process = Start-Process `
            -FilePath "msiexec.exe" `
            -ArgumentList $arguments `
            -Verb RunAs `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
    } catch {
        throw "Java installation needs administrator approval. UAC was cancelled or blocked."
    }

    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Java installer returned exit code $($process.ExitCode). See $LogPath"
    }
}

function Install-Idea {
    param(
        [string]$InstallerPath,
        [string]$IdeaHome,
        [string]$ConfigPath,
        [string]$LogPath
    )

    if (Get-Process -Name "idea64", "idea" -ErrorAction SilentlyContinue) {
        throw "IntelliJ IDEA is running. Close it and run the installer again."
    }

    $config = @"
mode=user
launcher64=1
updatePATH=0
updateContextMenu=0
.java=0
.groovy=0
.kt=0
"@
    [IO.File]::WriteAllText($ConfigPath, $config, [Text.Encoding]::ASCII)

    $argumentLine = "/S /CONFIG=`"$ConfigPath`" /LOG=`"$LogPath`" /D=$IdeaHome"
    $process = Start-Process `
        -FilePath $InstallerPath `
        -ArgumentList $argumentLine `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "IntelliJ IDEA installer returned exit code $($process.ExitCode). See $LogPath"
    }
}

function New-IdeaDesktopShortcut {
    param([string]$IdeaHome)

    $ideaExe = Join-Path $IdeaHome "bin\idea64.exe"
    if (-not (Test-Path -LiteralPath $ideaExe -PathType Leaf)) {
        throw "IntelliJ IDEA executable was not found at $ideaExe"
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "IntelliJ IDEA $IdeaVersion.lnk"
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $ideaExe
        $shortcut.WorkingDirectory = Join-Path $IdeaHome "bin"
        $shortcut.IconLocation = "$ideaExe,0"
        $shortcut.Description = "IntelliJ IDEA $IdeaVersion"
        $shortcut.Save()
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function Test-JavaInstallation {
    param([string]$JdkHome)

    $javaExe = Join-Path $JdkHome "bin\java.exe"
    $javacExe = Join-Path $JdkHome "bin\javac.exe"
    if (-not (Test-Path -LiteralPath $javaExe -PathType Leaf)) {
        throw "java.exe was not found at $javaExe"
    }
    if (-not (Test-Path -LiteralPath $javacExe -PathType Leaf)) {
        throw "javac.exe was not found at $javacExe"
    }

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $javaExe -version 2>&1 | Out-Null
    $javaExitCode = $LASTEXITCODE
    & $javacExe -version 2>&1 | Out-Null
    $javacExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($javaExitCode -ne 0) {
        throw "java.exe verification failed."
    }
    if ($javacExitCode -ne 0) {
        throw "javac.exe verification failed."
    }

    $userJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    $machineJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    $effectiveJavaHome = if ($userJavaHome) { $userJavaHome } else { $machineJavaHome }
    if (-not $effectiveJavaHome -or $effectiveJavaHome.TrimEnd("\") -ine $JdkHome.TrimEnd("\")) {
        throw "JAVA_HOME was not configured to $JdkHome."
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $effectivePath = @($machinePath, $userPath) -join ";"
    if ($effectivePath -notmatch [regex]::Escape($JdkHome)) {
        throw "PATH does not contain the installed JDK."
    }
}

function Remove-DownloadDirectory {
    param(
        [string]$Root,
        [string]$DownloadDirectory
    )

    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\") + "\"
    $resolvedDownloads = [IO.Path]::GetFullPath($DownloadDirectory)
    if (-not $resolvedDownloads.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside the installation root."
    }
    if (Test-Path -LiteralPath $resolvedDownloads) {
        Remove-Item -LiteralPath $resolvedDownloads -Recurse -Force
    }
}

try {
    Write-Section "Java + IDEA minimal installer"
    if ($DryRun) {
        Write-Line "[INFO] Dry run: no files will be created and no installers will run."
    }

    $root = $null
    $downloadDirectory = $null
    $javaLog = $null
    $ideaLog = $null
    $ideaConfig = $null

    $existingJava = if ($IgnoreExisting) { $null } else { Get-ExistingJavaInstallation }
    $existingIdea = if ($IgnoreExisting) { $null } else { Get-ExistingIdeaInstallation }
    $javaAction = if ($existingJava) { "use" } else { "install" }
    $ideaAction = if ($existingIdea) { "use" } else { "install" }

    if ($existingJava) {
        Write-Line -Message "[INFO] Found $($existingJava.Name) at $($existingJava.Home)" -Color Green
    }
    if ($existingIdea) {
        Write-Line -Message "[INFO] Found $($existingIdea.Name) at $($existingIdea.Home)" -Color Green
    }
    if ($javaAction -eq "use" -and $ideaAction -eq "use") {
        Write-Line "[INFO] Existing compatible versions will be reused. No download is needed."
    }

    if ($javaAction -eq "install" -or $ideaAction -eq "install") {
        $drives = Get-FixedDriveChoices
        $drive = Select-InstallDrive -Drives $drives
        $root = Get-InstallRoot -DriveLetter $drive.DeviceId
        $downloadDirectory = Join-Path $root ".downloads"
        $javaLog = Join-Path $root "java-install.log"
        $ideaLog = Join-Path $root "idea-install.log"
        $ideaConfig = Join-Path $root "idea-silent.config"

        Write-Line "[INFO] Drive: $($drive.DeviceId)"
        Write-Line "[INFO] Root:  $root"
    }

    $jdkHome = if ($existingJava) { $existingJava.Home } else { Join-Path $root "jdk-$JdkMajorVersion" }
    $ideaHome = if ($existingIdea) { $existingIdea.Home } else { Join-Path $root "idea-$IdeaVersion" }
    Write-Line "[INFO] Java:  $jdkHome"
    Write-Line "[INFO] IDEA:  $ideaHome"

    $javaPackage = if ($javaAction -eq "install") { Resolve-JavaPackage } else { $null }
    $ideaChecksum = if ($ideaAction -eq "install") { Resolve-IdeaChecksum } else { $null }

    if ($DryRun) {
        if ($javaAction -eq "use") {
            Write-Line "[DRY-RUN] Reuse Java: $jdkHome"
        } else {
            Write-Line "[DRY-RUN] Java version: $($javaPackage.Version)"
            Write-Line "[DRY-RUN] Java resolution: $($javaPackage.SourceUri)"
            foreach ($source in $javaPackage.Uris) {
                Write-Line "[DRY-RUN] Java source: $source"
            }
        }
        if ($ideaAction -eq "use") {
            Write-Line "[DRY-RUN] Reuse IDEA: $ideaHome"
        } else {
            Write-Line "[DRY-RUN] IDEA SHA-256: $ideaChecksum"
            foreach ($source in $IdeaUris) {
                Write-Line "[DRY-RUN] IDEA source: $source"
            }
        }
        if ($root) {
            Write-Line "[DRY-RUN] Planned root: $root"
        }
        exit 0
    }

    if ($javaAction -eq "install" -or $ideaAction -eq "install") {
        Ensure-RootDirectory -Root $root
        New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null
    }

    if ($javaAction -eq "install") {
        Install-Java `
            -Package $javaPackage `
            -DownloadDirectory $downloadDirectory `
            -JdkHome $jdkHome `
            -LogPath $javaLog
    }

    if ($ideaAction -eq "install") {
        $ideaInstallerPath = Join-Path $downloadDirectory $IdeaInstallerName
        Get-VerifiedFile `
            -Uri $IdeaUris `
            -Destination $ideaInstallerPath `
            -ExpectedSha256 $ideaChecksum `
            -Label "Download IntelliJ IDEA $IdeaVersion" | Out-Null
        Install-Idea `
            -InstallerPath $ideaInstallerPath `
            -IdeaHome $ideaHome `
            -ConfigPath $ideaConfig `
            -LogPath $ideaLog
    }

    Set-JavaEnvironment -JdkHome $jdkHome
    Test-JavaInstallation -JdkHome $jdkHome
    New-IdeaDesktopShortcut -IdeaHome $ideaHome
    if ($root -and $downloadDirectory) {
        Remove-DownloadDirectory -Root $root -DownloadDirectory $downloadDirectory
    }

    Write-Section "Installation complete"
    Write-Line -Message "[OK] Java:  $jdkHome" -Color Green
    Write-Line -Message "[OK] IDEA:  $ideaHome" -Color Green
    Write-Line -Message "[OK] Desktop shortcut: IntelliJ IDEA $IdeaVersion.lnk" -Color Green

    if (-not $NoLaunch) {
        Start-Process -FilePath (Join-Path $ideaHome "bin\idea64.exe") | Out-Null
    }
    exit 0
} catch {
    Write-Line
    Write-Line -Message "[ERROR] $($_.Exception.Message)" -Color Red
    if ($root) {
        Write-Line -Message "[INFO] Failed downloads and logs are kept under $root." -Color Yellow
    }
    exit 1
}
