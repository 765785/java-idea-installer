$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-InstallerPowerShellSource {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw
    $marker = "# POWERSHELL_BEGIN"
    $index = $content.LastIndexOf($marker, [StringComparison]::Ordinal)
    if ($index -lt 0) {
        throw "install-windows.bat does not contain the PowerShell marker."
    }

    return $content.Substring($index + $marker.Length)
}

function Get-InstallerPowerShellDefinitions {
    param([string]$Source)

    $matches = [regex]::Matches($Source, "(?m)^try \{\r?$")
    if ($matches.Count -eq 0) {
        throw "install-windows.bat does not contain the top-level try block."
    }

    $match = $matches[$matches.Count - 1]
    return $Source.Substring(0, $match.Index)
}

function New-TestDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("java-installer-test-" + [guid]::NewGuid().ToString("N"))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

$installerPath = Join-Path $repoRoot "scripts\install-windows.bat"
Assert-True (Test-Path -LiteralPath $installerPath -PathType Leaf) "Missing scripts\install-windows.bat."

$powerShellSource = Get-InstallerPowerShellSource -Path $installerPath
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseInput(
    $powerShellSource,
    [ref]$tokens,
    [ref]$errors
) | Out-Null
Assert-True ($errors.Count -eq 0) "Embedded PowerShell has syntax errors: $($errors.Message -join '; ')"

$dryRunOutput = & cmd.exe /d /c "`"$installerPath`" --dry-run --ignore-existing" 2>&1 | Out-String
$dryRunExitCode = $LASTEXITCODE
Assert-True ($dryRunExitCode -eq 0) "--dry-run returned $dryRunExitCode. Output: $dryRunOutput"
Assert-True ($dryRunOutput -match "\[DRY-RUN\] Java resolution:") "--dry-run did not report how the Java version was resolved."
Assert-True ($dryRunOutput -match "ideaIC-2025\.2\.6\.2\.exe") "--dry-run did not report the IDEA installer."
Assert-True ($dryRunOutput -match "jdk-21") "--dry-run did not report the JDK target."
Assert-True ($dryRunOutput -match "mirrors\.tuna\.tsinghua\.edu\.cn/Adoptium/21/jdk/x64/windows/") "--dry-run did not report the Tsinghua Java mirror."
Assert-True ($dryRunOutput -match "mirrors\.nju\.edu\.cn/adoptium/21/jdk/x64/windows/") "--dry-run did not report the Nanjing University Java mirror."
Assert-True ($dryRunOutput -match "github\.com/adoptium/temurin21-binaries") "--dry-run did not report the official GitHub Java fallback."
Assert-True ($dryRunOutput -match "download-cdn\.jetbrains\.com/idea/ideaIC-2025\.2\.6\.2\.exe") "--dry-run did not report the JetBrains CDN."
Assert-True ($dryRunOutput -match "download\.jetbrains\.com/idea/ideaIC-2025\.2\.6\.2\.exe") "--dry-run did not report the official JetBrains fallback."
Assert-True ($dryRunOutput -match "\[DRY-RUN\] Java size:") "--dry-run did not report the Java download size."
Assert-True ($dryRunOutput -match "\[DRY-RUN\] IDEA size:") "--dry-run did not report the IDEA download size."

$tunaIndex = $dryRunOutput.IndexOf("https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jdk/x64/windows/", [StringComparison]::Ordinal)
$njuIndex = $dryRunOutput.IndexOf("https://mirrors.nju.edu.cn/adoptium/21/jdk/x64/windows/", [StringComparison]::Ordinal)
$githubJavaIndex = $dryRunOutput.IndexOf("https://github.com/adoptium/temurin21-binaries", [StringComparison]::Ordinal)
Assert-True ($tunaIndex -ge 0 -and $njuIndex -gt $tunaIndex -and $githubJavaIndex -gt $njuIndex) "Java download source order is incorrect."

$ideaCdnIndex = $dryRunOutput.IndexOf("https://download-cdn.jetbrains.com/idea/", [StringComparison]::Ordinal)
$ideaOfficialIndex = $dryRunOutput.IndexOf("https://download.jetbrains.com/idea/", [StringComparison]::Ordinal)
Assert-True ($ideaCdnIndex -ge 0 -and $ideaOfficialIndex -gt $ideaCdnIndex) "IDEA download source order is incorrect."

$installerSource = Get-Content -LiteralPath $installerPath -Raw
Assert-True ($installerSource -match "function Get-ExistingJavaInstallation") "installer does not detect an existing JDK."
Assert-True ($installerSource -match "function Get-ExistingIdeaInstallation") "installer does not detect an existing IDEA."
Assert-True ($installerSource -match "Existing compatible versions will be reused") "installer does not report component reuse."
Assert-True ($installerSource -match "454cfd334b9ca91c96dd8c2de97fcef6b9f1f98be9172ff076711f1c6b44e4e0") "installer is missing the pinned Java checksum."
Assert-True ($installerSource -match "8393c2c9ccbd8581d646f01f0b6f0e7f78e58ebbe5cd8cbd95f9e236518e9fe8") "installer is missing the pinned IDEA checksum."
Assert-True ($installerSource -match "Enter drive number or letter") "installer prompt does not accept a drive number or letter."
Assert-True ($installerSource -match "--progress-bar") "installer download does not show a progress bar."
Assert-True ($installerSource -match "Keep this window open while downloading") "installer does not tell the user to keep the window open."
Assert-True ($installerSource -match "catch \[System\.OperationCanceledException\]") "installer does not handle user cancellation separately."
Assert-True ($installerSource -match "(?m)^\s*exit 2\s*$") "installer does not return exit code 2 for user cancellation."
Assert-True ($installerSource -notmatch "(?m)^\s*Uri = \$OfficialUri\s*$") "installer still exposes the unused singular Uri field."

$definitions = Get-InstallerPowerShellDefinitions -Source $powerShellSource
Invoke-Expression $definitions
$MaximumAttempts = 1

$script:testDriveAnswer = "1"
function Read-Host {
    param([string]$Prompt)
    return $script:testDriveAnswer
}

$testDrives = @(
    [pscustomobject]@{ DeviceId = "C:"; Label = "OS"; FreeSpace = 100GB; Size = 200GB },
    [pscustomobject]@{ DeviceId = "D:"; Label = "Data"; FreeSpace = 100GB; Size = 200GB }
)
$DryRun = $false
foreach ($answer in @("1", "C", "")) {
    $script:testDriveAnswer = $answer
    $selectedDrive = Select-InstallDrive -Drives $testDrives
    Assert-True ($selectedDrive.DeviceId -eq "C:") "drive input '$answer' did not select the first drive."
}

$pathTestRoot = New-TestDirectory
try {
    $olderHome = Join-Path $pathTestRoot "older"
    $targetHome = Join-Path $pathTestRoot "target"
    $olderBin = Join-Path $olderHome "bin"
    $targetBin = Join-Path $targetHome "bin"
    [IO.Directory]::CreateDirectory($olderBin) | Out-Null
    [IO.Directory]::CreateDirectory($targetBin) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $olderBin "java.exe"), @())
    [IO.File]::WriteAllBytes((Join-Path $targetBin "java.exe"), @())
    [IO.File]::WriteAllBytes((Join-Path $olderBin "javac.exe"), @())
    [IO.File]::WriteAllBytes((Join-Path $targetBin "javac.exe"), @())

    $firstExecutable = Get-FirstExecutablePath -PathEntries @($olderBin, $targetBin) -ExecutableName "java.exe"
    Assert-True ($firstExecutable -ieq (Join-Path $olderBin "java.exe")) "PATH lookup did not preserve Windows precedence."
    Assert-True (-not (Test-JavaCommandResolution -JdkHome $targetHome -MachinePath $olderBin -UserPath $targetBin)) "PATH verification accepted an older machine-level JDK."
    Assert-True (Test-JavaCommandResolution -JdkHome $targetHome -MachinePath $targetBin -UserPath $olderBin) "PATH verification rejected the target JDK at the front."

    $mergedPath = Merge-PathEntryFirst -PathValue "$olderBin;$targetBin;$olderBin" -Entry $targetBin
    Assert-True (($mergedPath -split ";")[0] -ieq $targetBin) "target JDK bin was not moved to the front of PATH."
    Assert-True ((@($mergedPath -split ";" | Where-Object { $_ -ieq $targetBin })).Count -eq 1) "target JDK bin was not deduplicated in PATH."
} finally {
    [IO.Directory]::Delete($pathTestRoot, $true)
}

$downloadTestRoot = New-TestDirectory
try {
    $badSource = Join-Path $downloadTestRoot "bad.bin"
    $goodSource = Join-Path $downloadTestRoot "good.bin"
    $destination = Join-Path $downloadTestRoot "result.bin"
    [IO.File]::WriteAllText($badSource, "baad-source", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($goodSource, "good-source", [Text.Encoding]::ASCII)
    $goodHash = Get-Sha256 -Path $goodSource
    $goodSize = (Get-Item -LiteralPath $goodSource).Length
    Assert-True ((Get-Item -LiteralPath $badSource).Length -eq $goodSize) "hash fallback fixture sizes must match."

    $script:downloadFixtures = @{
        "bad-source" = $badSource
        "good-source" = $goodSource
    }
    function Invoke-DownloadSource {
        param([string]$Source, [string]$Destination)
        Copy-Item -LiteralPath $script:downloadFixtures[$Source] -Destination $Destination -Force
    }

    $verifiedPath = Get-VerifiedFile `
        -Uri @("bad-source", "good-source") `
        -Destination $destination `
        -ExpectedSha256 $goodHash `
        -ExpectedSize $goodSize `
        -Label "hash fallback test"
    Assert-True (([IO.File]::ReadAllText($verifiedPath)) -eq "good-source") "hash mismatch did not fall through to the next source."
} finally {
    [IO.Directory]::Delete($downloadTestRoot, $true)
}

$cancelError = [pscustomobject]@{
    Exception = [pscustomobject]@{
        NativeErrorCode = 1223
        Message = "The operation was canceled by the user."
        InnerException = $null
    }
}
$genericError = [pscustomobject]@{
    Exception = [pscustomobject]@{
        NativeErrorCode = 5
        Message = "Access is denied."
        InnerException = $null
    }
}
Assert-True (Test-IsUserCancellation -ErrorRecord $cancelError) "UAC cancellation was not recognized."
Assert-True (-not (Test-IsUserCancellation -ErrorRecord $genericError)) "generic failure was misclassified as cancellation."

$elevationTestRoot = New-TestDirectory
try {
    $fakeJdkHome = Join-Path $elevationTestRoot "fake-jdk"
    [IO.Directory]::CreateDirectory((Join-Path $fakeJdkHome "bin")) | Out-Null
    $elevationResultPath = Join-Path $elevationTestRoot "result.txt"

    function Start-Process {
        param(
            [string]$FilePath,
            [object]$ArgumentList,
            [string]$Verb,
            [string]$WindowStyle,
            [switch]$Wait,
            [switch]$PassThru
        )

        Assert-True ($FilePath -eq "powershell.exe") "elevated helper did not launch Windows PowerShell."
        $arguments = @($ArgumentList)
        $encodedIndex = [Array]::IndexOf($arguments, "-EncodedCommand")
        Assert-True ($encodedIndex -ge 0) "elevated helper did not use EncodedCommand."
        $helper = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($arguments[$encodedIndex + 1]))
        $helperTokens = $null
        $helperErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput(
            $helper,
            [ref]$helperTokens,
            [ref]$helperErrors
        ) | Out-Null
        Assert-True ($helperErrors.Count -eq 0) "elevated helper has syntax errors: $($helperErrors.Message -join '; ')"

        "OK" | Set-Content -LiteralPath $elevationResultPath -Encoding ASCII
        return [pscustomobject]@{ ExitCode = 0 }
    }

    Invoke-ElevatedJavaEnvironment -JdkHome $fakeJdkHome -ResultPath $elevationResultPath
    Assert-True (((Get-Content -LiteralPath $elevationResultPath -Raw).Trim()) -eq "OK") "elevated helper result protocol failed."
} finally {
    [IO.Directory]::Delete($elevationTestRoot, $true)
}

$indexPath = Join-Path $repoRoot "index.html"
$indexHtml = Get-Content -LiteralPath $indexPath -Raw
$downloadLinks = [regex]::Matches($indexHtml, 'href="([^"]*install-windows\.bat[^"]*)"')
Assert-True ($downloadLinks.Count -eq 1) "index.html must contain exactly one install-windows.bat download link."
Assert-True ($indexHtml -notmatch "app\.js") "index.html still loads the removed app.js."
Assert-True ($indexHtml -notmatch "检测报告") "index.html still contains the old detection-report UI."
Assert-True ($indexHtml -notmatch "macOS") "index.html still contains the removed macOS entry."
Assert-True ($indexHtml -match "更多信息") "index.html does not explain the SmartScreen warning."
Assert-True ($indexHtml -match "约 1\.1 GB") "index.html does not explain the total download size."
Assert-True ($indexHtml -match "不要关闭黑色安装窗口") "index.html does not explain that the installer window must stay open."

$stylesPath = Join-Path $repoRoot "styles.css"
$styles = Get-Content -LiteralPath $stylesPath -Raw
Assert-True ($styles -match "(?m)^\s*min-width:\s*1024px;") "styles.css must use a fixed desktop canvas."
Assert-True ($styles -notmatch "@media\s*\(max-width") "styles.css must not contain mobile layout breakpoints."

$removedPaths = @(
    "app.js",
    "schemas\detection-result.schema.json",
    "schemas\install-progress.schema.json",
    "scripts\detect.bat",
    "scripts\detect.command",
    "scripts\detect.sh",
    "scripts\install.bat",
    "scripts\install.command",
    "scripts\install.sh",
    "scripts\uninstall.bat",
    "scripts\uninstall.command",
    "scripts\uninstall.sh",
    "scripts\package-toolkits.ps1",
    "scripts\package-toolkits.sh",
    "scripts\progress.html",
    "scripts\progress.js",
    "scripts\repair-bridge.ps1",
    "scripts\repair-bridge.py",
    "scripts\repair-launch.html",
    "scripts\repair-launch.js",
    "scripts\repair-run.bat",
    "scripts\repair-run.sh",
    "scripts\lib\common-functions.bat",
    "scripts\lib\common-functions.sh",
    "scripts\lib\progress-server.ps1",
    "scripts\lib\progress-server.py",
    "scripts\lib\windows.ps1"
)

foreach ($relativePath in $removedPaths) {
    $fullPath = Join-Path $repoRoot $relativePath
    Assert-True (-not (Test-Path -LiteralPath $fullPath)) "Legacy file still exists: $relativePath"
}

Write-Host "installer contract checks passed"
