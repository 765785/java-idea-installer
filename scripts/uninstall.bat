@echo off
setlocal EnableExtensions
title Java Setup - Uninstall

set "SCRIPT_DIR=%~dp0"
set "ENGINE=%SCRIPT_DIR%lib\windows.ps1"
set "COMMON=%SCRIPT_DIR%lib\common-functions.bat"

if not exist "%ENGINE%" goto :missing_toolkit
if not exist "%COMMON%" goto :missing_toolkit

call "%COMMON%"
set EXTRA_ARGS=

:parse_args
if "%~1"=="" goto :invoke
if /I "%~1"=="--keep-settings" (
  set EXTRA_ARGS=%EXTRA_ARGS% -KeepSettings
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
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Action uninstall %EXTRA_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" echo [OK] Uninstall flow completed.
if "%EXIT_CODE%"=="1" echo [ERROR] Uninstall failed. Review the output above.
echo.
if /I not "%JAVA_SETUP_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%

:missing_toolkit
echo [ERROR] The toolkit is incomplete.
echo Download and extract the complete Windows toolkit, then run uninstall.bat again.
if /I not "%JAVA_SETUP_NO_PAUSE%"=="1" pause
exit /b 1
