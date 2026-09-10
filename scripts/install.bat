@echo off
setlocal EnableExtensions
title Java Setup - Install

set "SCRIPT_DIR=%~dp0"
set "ENGINE=%SCRIPT_DIR%lib\windows.ps1"
set "COMMON=%SCRIPT_DIR%lib\common-functions.bat"

if not exist "%ENGINE%" goto :missing_toolkit
if not exist "%COMMON%" goto :missing_toolkit

call "%COMMON%"
set EXTRA_ARGS=

:parse_args
if "%~1"=="" goto :invoke
if /I "%~1"=="--fix" (
  set EXTRA_ARGS=%EXTRA_ARGS% -Fix "%~2"
  shift
  shift
  goto :parse_args
)
if /I "%~1"=="--resume" (
  set EXTRA_ARGS=%EXTRA_ARGS% -Resume
  shift
  goto :parse_args
)
if /I "%~1"=="--dry-run" (
  set EXTRA_ARGS=%EXTRA_ARGS% -DryRun
  shift
  goto :parse_args
)
if /I "%~1"=="--output" (
  set EXTRA_ARGS=%EXTRA_ARGS% -OutputDirectory "%~2"
  shift
  shift
  goto :parse_args
)
shift
goto :parse_args

:invoke
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action install %EXTRA_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [OK] Installation and environment configuration completed.
if "%EXIT_CODE%"=="10" echo [INFO] Some components still need attention.
if "%EXIT_CODE%"=="20" echo [INFO] Some steps completed with warnings.
if "%EXIT_CODE%"=="1" echo [ERROR] Installation failed. Review the output above.
echo.
if /I not "%JAVA_SETUP_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%

:missing_toolkit
echo [INFO] The standalone script will download the verified toolkit...
call :bootstrap
if errorlevel 1 goto :bootstrap_failed
call "%LOCALAPPDATA%\JavaIdeaInstaller\windows-toolkit\install.bat" %*
exit /b %ERRORLEVEL%

:bootstrap
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $base='https://765785.github.io/java-idea-installer/downloads/'; $dir=Join-Path $env:LOCALAPPDATA 'JavaIdeaInstaller\windows-toolkit'; New-Item -ItemType Directory -Force -Path $dir | Out-Null; $sums=Invoke-WebRequest -UseBasicParsing -Uri ($base+'SHA256SUMS.txt') -TimeoutSec 30; $line=@($sums.Content -split [Environment]::NewLine | Where-Object { $_ -match '([0-9a-f]{64})\s+java-idea-toolkit-windows\.zip' })[0]; if(-not $line){ throw 'SHA256SUMS.txt does not contain the Windows toolkit.' }; $expected=([regex]::Match($line,'[0-9a-f]{64}').Value).ToLowerInvariant(); $zip=Join-Path $dir 'toolkit.zip'; Invoke-WebRequest -UseBasicParsing -Uri ($base+'java-idea-toolkit-windows.zip') -OutFile $zip -TimeoutSec 300; $sha=[Security.Cryptography.SHA256]::Create(); $stream=[IO.File]::OpenRead($zip); $actual=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant(); $stream.Dispose(); $sha.Dispose(); if($actual -ne $expected){ Remove-Item -LiteralPath $zip -Force; throw 'Windows toolkit SHA-256 verification failed.' }; Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force; Remove-Item -LiteralPath $zip -Force"
exit /b %ERRORLEVEL%

:bootstrap_failed
echo [ERROR] Toolkit download or verification failed.
echo Open https://765785.github.io/java-idea-installer/ and download the Windows toolkit manually.
if /I not "%JAVA_SETUP_NO_PAUSE%"=="1" pause
exit /b 1
