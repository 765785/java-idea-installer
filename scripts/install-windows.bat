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
$JdkMajorVersion = 25
$IdeaVersion = "2025.2.6.2"
$IdeaInstallerName = "ideaIC-$IdeaVersion.exe"
$IdeaUri = "https://download.jetbrains.com/idea/$IdeaInstallerName"
$IdeaChecksumUri = "$IdeaUri.sha256"
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
        [string]$Uri,
        [string]$Destination,
        [string]$ExpectedSha256,
        [string]$Label
    )

    Invoke-WithRetry -Label $Label -Operation {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force
        }

        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers $Headers -OutFile $Destination -TimeoutSec 900
            $actual = Get-Sha256 -Path $Destination
            if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
                throw "SHA-256 mismatch. Expected $ExpectedSha256, got $actual"
            }
        } catch {
            if (Test-Path -LiteralPath $Destination) {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            }
            throw
        }
    } | Out-Null

    return $Destination
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

function Resolve-JavaPackage {
    $uri = "https://api.adoptium.net/v3/assets/latest/$JdkMajorVersion/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse&installer_type=msi"
    $response = Invoke-WithRetry -Label "Resolve latest JDK $JdkMajorVersion LTS" -Operation {
        return Invoke-RestMethod -Uri $uri -Headers $Headers -TimeoutSec 30
    }

    $asset = @($response)[0]
    $installer = $asset.binary.installer
    if (-not $installer.link -or -not $installer.checksum) {
        throw "Adoptium did not return a Windows MSI package."
    }

    return [pscustomobject]@{
        Version = [string]$asset.version.semver
        SourceUri = $uri
        Uri = [string]$installer.link
        Sha256 = ([string]$installer.checksum).ToLowerInvariant()
    }
}

function Resolve-IdeaChecksum {
    $content = Get-RemoteText -Uri $IdeaChecksumUri -Label "Resolve IDEA checksum"
    $match = [regex]::Match($content, "[a-fA-F0-9]{64}")
    if (-not $match.Success) {
        throw "JetBrains checksum file does not contain a SHA-256 value."
    }
    return $match.Value.ToLowerInvariant()
}

function Read-ExistingChoice {
    param(
        [string]$Name,
        [string]$Path
    )

    while ($true) {
        Write-Line
        Write-Line -Message "[INFO] $Name already exists at $Path" -Color Yellow
        $answer = (Read-Host "Choose [S]kip, [R]einstall, or [C]ancel (default S)").Trim().ToUpperInvariant()
        if (-not $answer -or $answer -eq "S") {
            return "skip"
        }
        if ($answer -eq "R") {
            return "reinstall"
        }
        if ($answer -eq "C") {
            return "cancel"
        }
        Write-Line -Message "[WARN] Enter S, R, or C." -Color Yellow
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

    $installerName = [IO.Path]::GetFileName(([Uri]$Package.Uri).AbsolutePath)
    $installerPath = Join-Path $DownloadDirectory $installerName
    Get-VerifiedFile `
        -Uri $Package.Uri `
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

    $machineJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    $userJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    $effectiveJavaHome = if ($machineJavaHome) { $machineJavaHome } else { $userJavaHome }
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

    $drives = Get-FixedDriveChoices
    $drive = Select-InstallDrive -Drives $drives
    $root = Get-InstallRoot -DriveLetter $drive.DeviceId
    $jdkHome = Join-Path $root "jdk-$JdkMajorVersion"
    $ideaHome = Join-Path $root "idea-$IdeaVersion"
    $downloadDirectory = Join-Path $root ".downloads"
    $javaLog = Join-Path $root "java-install.log"
    $ideaLog = Join-Path $root "idea-install.log"
    $ideaConfig = Join-Path $root "idea-silent.config"

    Write-Line "[INFO] Drive: $($drive.DeviceId)"
    Write-Line "[INFO] Root:  $root"
    Write-Line "[INFO] Java:  $jdkHome"
    Write-Line "[INFO] IDEA:  $ideaHome"

    $javaPackage = Resolve-JavaPackage
    $ideaChecksum = Resolve-IdeaChecksum

    if ($DryRun) {
        Write-Line "[DRY-RUN] Java version: $($javaPackage.Version)"
        Write-Line "[DRY-RUN] Adoptium API: $($javaPackage.SourceUri)"
        Write-Line "[DRY-RUN] Java MSI: $($javaPackage.Uri)"
        Write-Line "[DRY-RUN] IDEA EXE: $IdeaUri"
        Write-Line "[DRY-RUN] IDEA SHA-256: $ideaChecksum"
        Write-Line "[DRY-RUN] Planned root: $root"
        exit 0
    }

    Ensure-RootDirectory -Root $root
    New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null

    $javaAction = "install"
    $javaExe = Join-Path $jdkHome "bin\java.exe"
    if (Test-Path -LiteralPath $javaExe -PathType Leaf) {
        $javaAction = Read-ExistingChoice -Name "JDK $JdkMajorVersion" -Path $jdkHome
    }
    if ($javaAction -eq "cancel") {
        exit 2
    }

    $ideaAction = "install"
    $ideaExe = Join-Path $ideaHome "bin\idea64.exe"
    if (Test-Path -LiteralPath $ideaExe -PathType Leaf) {
        $ideaAction = Read-ExistingChoice -Name "IntelliJ IDEA $IdeaVersion" -Path $ideaHome
    }
    if ($ideaAction -eq "cancel") {
        exit 2
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
            -Uri $IdeaUri `
            -Destination $ideaInstallerPath `
            -ExpectedSha256 $ideaChecksum `
            -Label "Download IntelliJ IDEA $IdeaVersion" | Out-Null
        Install-Idea `
            -InstallerPath $ideaInstallerPath `
            -IdeaHome $ideaHome `
            -ConfigPath $ideaConfig `
            -LogPath $ideaLog
    }

    Test-JavaInstallation -JdkHome $jdkHome
    New-IdeaDesktopShortcut -IdeaHome $ideaHome
    Remove-DownloadDirectory -Root $root -DownloadDirectory $downloadDirectory

    Write-Section "Installation complete"
    Write-Line -Message "[OK] Java:  $jdkHome" -Color Green
    Write-Line -Message "[OK] IDEA:  $ideaHome" -Color Green
    Write-Line -Message "[OK] Desktop shortcut: IntelliJ IDEA $IdeaVersion.lnk" -Color Green

    Start-Process -FilePath (Join-Path $ideaHome "bin\idea64.exe") | Out-Null
    exit 0
} catch {
    Write-Line
    Write-Line -Message "[ERROR] $($_.Exception.Message)" -Color Red
    if ($root) {
        Write-Line -Message "[INFO] Failed downloads and logs are kept under $root." -Color Yellow
    }
    exit 1
}
