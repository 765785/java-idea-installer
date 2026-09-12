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

$installerSource = Get-Content -LiteralPath $installerPath -Raw
Assert-True ($installerSource -match "function Get-ExistingJavaInstallation") "installer does not detect an existing JDK."
Assert-True ($installerSource -match "function Get-ExistingIdeaInstallation") "installer does not detect an existing IDEA."
Assert-True ($installerSource -match "Existing compatible versions will be reused") "installer does not report component reuse."

$indexPath = Join-Path $repoRoot "index.html"
$indexHtml = Get-Content -LiteralPath $indexPath -Raw
$downloadLinks = [regex]::Matches($indexHtml, 'href="([^"]*install-windows\.bat[^"]*)"')
Assert-True ($downloadLinks.Count -eq 1) "index.html must contain exactly one install-windows.bat download link."
Assert-True ($indexHtml -notmatch "app\.js") "index.html still loads the removed app.js."
Assert-True ($indexHtml -notmatch "检测报告") "index.html still contains the old detection-report UI."
Assert-True ($indexHtml -notmatch "macOS") "index.html still contains the removed macOS entry."

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
