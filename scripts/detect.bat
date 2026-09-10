@echo off
setlocal EnableExtensions
title Java Setup - Detect

set "SCRIPT_DIR=%~dp0"
set "ENGINE=%SCRIPT_DIR%lib\windows.ps1"
set "COMMON=%SCRIPT_DIR%lib\common-functions.bat"

if not exist "%ENGINE%" goto :missing_toolkit
if not exist "%COMMON%" goto :missing_toolkit

call "%COMMON%"
set EXTRA_ARGS=

:parse_args
if "%~1"=="" goto :invoke
if /I "%~1"=="--output" (
  set EXTRA_ARGS=%EXTRA_ARGS% -OutputDirectory "%~2"
  shift
  shift
  goto :parse_args
)
if /I "%~1"=="--open-page" (
  set EXTRA_ARGS=%EXTRA_ARGS% -OpenPage "%~2"
  shift
  shift
  goto :parse_args
)
shift
goto :parse_args

:invoke
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action detect %EXTRA_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [OK] Detection completed successfully.
if "%EXIT_CODE%"=="10" echo [INFO] Missing components were detected. Return to the website.
if "%EXIT_CODE%"=="20" echo [INFO] Fixable issues were detected. Return to the website.
if "%EXIT_CODE%"=="1" echo [ERROR] Detection failed. Review the output above.
echo.
if /I not "%JAVA_SETUP_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%

:missing_toolkit
echo [ERROR] The toolkit is incomplete.
echo Download and extract the complete Windows toolkit, then run detect.bat again.
if /I not "%JAVA_SETUP_NO_PAUSE%"=="1" pause
exit /b 1
