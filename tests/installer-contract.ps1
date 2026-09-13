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
Assert-True ($dryRunOutput -match "api\.adoptium\.net") "--dry-run did not report the Adoptium source."
Assert-True ($dryRunOutput -match "ideaIC-2025\.2\.6\.2\.exe") "--dry-run did not report the IDEA installer."
Assert-True ($dryRunOutput -match "jdk-25") "--dry-run did not report the JDK target."
Assert-True ($dryRunOutput -match "mirrors\.tuna\.tsinghua\.edu\.cn/Adoptium/25/jdk/x64/windows/") "--dry-run did not report the Tsinghua Java mirror."
Assert-True ($dryRunOutput -match "mirrors\.nju\.edu\.cn/adoptium/25/jdk/x64/windows/") "--dry-run did not report the Nanjing University Java mirror."
Assert-True ($dryRunOutput -match "github\.com/adoptium/temurin25-binaries") "--dry-run did not report the official GitHub Java fallback."
Assert-True ($dryRunOutput -match "download-cdn\.jetbrains\.com/idea/ideaIC-2025\.2\.6\.2\.exe") "--dry-run did not report the JetBrains CDN."
Assert-True ($dryRunOutput -match "download\.jetbrains\.com/idea/ideaIC-2025\.2\.6\.2\.exe") "--dry-run did not report the official JetBrains fallback."
Assert-True ($dryRunOutput -match "\[DRY-RUN\] Java size:") "--dry-run did not report the Java download size."
Assert-True ($dryRunOutput -match "\[DRY-RUN\] IDEA size:") "--dry-run did not report the IDEA download size."

$tunaIndex = $dryRunOutput.IndexOf("https://mirrors.tuna.tsinghua.edu.cn/Adoptium/25/jdk/x64/windows/", [StringComparison]::Ordinal)
$njuIndex = $dryRunOutput.IndexOf("https://mirrors.nju.edu.cn/adoptium/25/jdk/x64/windows/", [StringComparison]::Ordinal)
$githubJavaIndex = $dryRunOutput.IndexOf("https://github.com/adoptium/temurin25-binaries", [StringComparison]::Ordinal)
Assert-True ($tunaIndex -ge 0 -and $njuIndex -gt $tunaIndex -and $githubJavaIndex -gt $njuIndex) "Java download source order is incorrect."

$ideaCdnIndex = $dryRunOutput.IndexOf("https://download-cdn.jetbrains.com/idea/", [StringComparison]::Ordinal)
$ideaOfficialIndex = $dryRunOutput.IndexOf("https://download.jetbrains.com/idea/", [StringComparison]::Ordinal)
Assert-True ($ideaCdnIndex -ge 0 -and $ideaOfficialIndex -gt $ideaCdnIndex) "IDEA download source order is incorrect."

$installerSource = Get-Content -LiteralPath $installerPath -Raw
Assert-True ($installerSource -match "function Get-ExistingJavaInstallation") "installer does not detect an existing JDK."
Assert-True ($installerSource -match "function Get-ExistingIdeaInstallation") "installer does not detect an existing IDEA."
Assert-True ($installerSource -match "Existing compatible versions will be reused") "installer does not report component reuse."
Assert-True ($installerSource -match "517b3590be43120c34c3891d09c97a1eddc12da982208c4f5adf1bdc1b5e3f15") "installer is missing the pinned Java checksum."
Assert-True ($installerSource -match "8393c2c9ccbd8581d646f01f0b6f0e7f78e58ebbe5cd8cbd95f9e236518e9fe8") "installer is missing the pinned IDEA checksum."
Assert-True ($installerSource -match "Enter drive number or letter") "installer prompt does not accept a drive number or letter."
Assert-True ($installerSource -match "--progress-bar") "installer download does not show a progress bar."
Assert-True ($installerSource -match "Keep this window open while downloading") "installer does not tell the user to keep the window open."

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
