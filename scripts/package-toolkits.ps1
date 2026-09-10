[CmdletBinding()]
param(
    [string]$OutputDirectory = ".\_site\downloads"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDirectory))
New-Item -ItemType Directory -Force -Path $output | Out-Null

function New-ToolkitArchive {
    param(
        [string]$Name,
        [string[]]$Files
    )

    $archivePath = Join-Path $output $Name
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    $archive = [System.IO.Compression.ZipFile]::Open(
        $archivePath,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        foreach ($relativePath in $Files) {
            $source = Join-Path $scriptDirectory $relativePath
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Toolkit source file is missing: $relativePath"
            }
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $source,
                ($relativePath -replace "\\", "/"),
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally {
        $archive.Dispose()
    }
}

New-ToolkitArchive -Name "java-idea-toolkit-windows.zip" -Files @(
    "detect.bat",
    "install.bat",
    "uninstall.bat",
    "progress.html",
    "progress.js",
    "repair-launch.html",
    "repair-launch.js",
    "repair-bridge.ps1",
    "lib\common-functions.bat",
    "lib\windows.ps1",
    "lib\progress-server.ps1"
)

New-ToolkitArchive -Name "java-idea-toolkit-macos.zip" -Files @(
    "detect.command",
    "detect.sh",
    "install.command",
    "install.sh",
    "uninstall.command",
    "uninstall.sh",
    "progress.html",
    "progress.js",
    "repair-launch.html",
    "repair-launch.js",
    "repair-bridge.py",
    "lib\common-functions.sh",
    "lib\progress-server.py"
)

Write-Host "Built toolkits in $output" -ForegroundColor Green
Get-ChildItem -LiteralPath $output -Filter "java-idea-toolkit-*.zip" |
    Select-Object Name, Length

$checksums = Get-ChildItem -LiteralPath $output -Filter "java-idea-toolkit-*.zip" |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
[System.IO.File]::WriteAllLines(
    (Join-Path $output "SHA256SUMS.txt"),
    $checksums,
    [System.Text.Encoding]::ASCII
)
Write-Host "Wrote $(Join-Path $output 'SHA256SUMS.txt')" -ForegroundColor Green
