@echo off
setlocal

if not defined TOOLKIT_ROOT set "TOOLKIT_ROOT=%~dp0.."
if not defined REPORT_DIR set "REPORT_DIR=%USERPROFILE%\Downloads\java-setup-reports"
if not defined PROGRESS_DIR set "PROGRESS_DIR=%REPORT_DIR%\progress"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%" >nul 2>&1
if not exist "%PROGRESS_DIR%" mkdir "%PROGRESS_DIR%" >nul 2>&1

goto :eof

:java_setup_log_info
echo [INFO] %*
exit /b 0

:java_setup_log_ok
echo [OK] %*
exit /b 0

:java_setup_log_warn
echo [WARN] %*
exit /b 0

:java_setup_log_error
echo [ERROR] %* 1>&2
exit /b 0

:java_setup_open_url
start "" "%~1"
exit /b 0
